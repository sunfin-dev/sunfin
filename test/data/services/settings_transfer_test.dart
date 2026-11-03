import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/settings_transfer.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('what goes to another device', () {
    test('the user\'s choices do', () {
      for (final key in [
        'pref_sunfin_library_nicknames',
        'home_sections_config',
        'seerr_api_key_u1',
        'tmdbApiKey',
        'live_tv_last_channel_id',
      ]) {
        expect(SettingsTransfer.travels(key), isTrue, reason: key);
      }
    });

    test('the device\'s identity, sign-in, hardware and window stay', () {
      for (final key in [
        'device_id',
        'authentication_store_json',
        'pref_last_user_id',
        'window_width',
        'device_capability_codec',
        'pref_passthrough_truehd',
        'pref_audio_passthrough_mode',
        'last_external_rows_refresh_time',
        'last_playback_session',
      ]) {
        expect(SettingsTransfer.travels(key), isFalse, reason: key);
      }
    });

    test('nothing that looks like a login goes', () {
      for (final key in ['seerr_token_u1', 'trakt_Cookie', 'x_password']) {
        expect(SettingsTransfer.travels(key), isFalse, reason: key);
      }
    });
  });

  test(
    'a snapshot keeps every type and leaves the device\'s keys out',
    () async {
      final prefs = await _prefs({
        'device_id': 'shield',
        'a_bool': true,
        'an_int': 3,
        'a_double': 1.5,
        'a_string': 'x',
        'a_list': ['p', 'q'],
      });
      final snapshot = SettingsTransfer.snapshot(
        prefs,
        device: 'Android TV',
        now: DateTime.utc(2026, 10, 27),
      );
      expect(snapshot['device'], 'Android TV');
      expect(snapshot['values'], {
        'a_bool': ['b', true],
        'a_double': ['d', 1.5],
        'a_list': [
          'l',
          ['p', 'q'],
        ],
        'a_string': ['s', 'x'],
        'an_int': ['i', 3],
      });
    },
  );

  test('a large snapshot is split and joined again', () {
    final snapshot = <String, Object?>{
      'format': SettingsTransfer.formatVersion,
      'device': 'Android TV',
      'values': {
        'big': ['s', 'x' * (SettingsTransfer.chunkLength * 2 + 5)],
      },
    };
    final stored = SettingsTransfer.encode(snapshot);
    expect(stored['parts'], '3');
    expect(SettingsTransfer.decode(stored), snapshot);
  });

  test('a missing part or another format reads as no snapshot', () {
    final stored = SettingsTransfer.encode({
      'format': SettingsTransfer.formatVersion,
      'values': {
        'big': ['s', 'x' * (SettingsTransfer.chunkLength + 1)],
      },
    });
    expect(SettingsTransfer.decode(Map.of(stored)..remove('part1')), isNull);
    expect(
      SettingsTransfer.decode(
        SettingsTransfer.encode({'format': 99, 'values': {}}),
      ),
      isNull,
    );
    expect(SettingsTransfer.decode(const {}), isNull);
  });

  test(
    'importing mirrors the snapshot and keeps the device\'s own keys',
    () async {
      final shield = await _prefs({
        'device_id': 'shield',
        'theme': 'sunfin',
        'rows': ['resume', 'latest'],
        'volume_steps': 5,
      });
      final snapshot = SettingsTransfer.snapshot(shield, device: 'Android TV');

      final windows = await _prefs({
        'device_id': 'windows',
        'window_width': 1600.0,
        'theme': 'old',
        'only_on_windows': true,
      });
      final written = await SettingsTransfer.apply(windows, snapshot);

      expect(written, 3);
      expect(windows.getString('device_id'), 'windows');
      expect(windows.getDouble('window_width'), 1600.0);
      expect(windows.getString('theme'), 'sunfin');
      expect(windows.getStringList('rows'), ['resume', 'latest']);
      expect(windows.getInt('volume_steps'), 5);
      expect(windows.containsKey('only_on_windows'), isFalse);
    },
  );

  test('per-account settings land on the account signed in here', () async {
    // Each device makes up its own id for the server entry; the user's id
    // is the server's and the same everywhere.
    final shield = await _prefs({
      'pref_last_server_id': 'shield-entry',
      'pref_last_user_id': 'u1',
      'home_sections_config_shield-entry_u1': '[resume]',
      'seerr_enabled_u1': true,
      'library_sort_by_lib9': 'name',
    });
    final snapshot = SettingsTransfer.snapshot(shield, device: 'Android TV');
    expect(
      (snapshot['values'] as Map).keys,
      containsAll([
        'home_sections_config_{server}_{user}',
        'seerr_enabled_{user}',
        'library_sort_by_lib9',
      ]),
    );

    final windows = await _prefs({
      'pref_last_server_id': 'windows-entry',
      'pref_last_user_id': 'u1',
      'home_sections_config_windows-entry_u1': '[default]',
    });
    await SettingsTransfer.apply(windows, snapshot);

    expect(
      windows.getString('home_sections_config_windows-entry_u1'),
      '[resume]',
    );
    expect(windows.getBool('seerr_enabled_u1'), isTrue);
    expect(windows.getString('library_sort_by_lib9'), 'name');
    expect(
      windows.containsKey('home_sections_config_shield-entry_u1'),
      isFalse,
    );
    expect(windows.getString('pref_last_server_id'), 'windows-entry');
  });

  test('per-account settings wait for a sign-in', () async {
    final prefs = await _prefs({});
    await SettingsTransfer.apply(prefs, {
      'format': SettingsTransfer.formatVersion,
      'values': {
        'theme_{server}_{user}': ['s', 'sunfin'],
        'clock': ['b', true],
      },
    });
    expect(prefs.getKeys(), {'clock'});
  });

  test('Jellyfin\'s own empty entries don\'t break reading the account', () {
    final stored = DisplayPreferences.fromJson({
      'Id': SettingsTransfer.displayPreferencesId,
      'CustomPrefs': {
        'tvhome': null,
        'dashboardTheme': null,
        'skipForwardLength': '30000',
        ...SettingsTransfer.encode({
          'format': SettingsTransfer.formatVersion,
          'values': {
            'theme': ['s', 'sunfin'],
          },
        }),
      },
    });
    expect(stored.customPrefs.containsKey('tvhome'), isFalse);
    expect(SettingsTransfer.decode(stored.customPrefs)?['values'], {
      'theme': ['s', 'sunfin'],
    });
  });

  group('reset', () {
    test('puts the user\'s and the device\'s settings back', () {
      for (final key in [
        'home_sections_config',
        'pref_sunfin_library_nicknames',
        'hardware_decoding',
        'pref_audio_passthrough_mode',
        'player_volume',
        'pref_plugin_sync_initialized_srv1',
        'pref_setup_wizard_version_srv1',
      ]) {
        expect(SettingsTransfer.resets(key), isTrue, reason: key);
      }
    });

    test('keeps who is signed in and what was only recorded', () {
      for (final key in [
        'device_id',
        'authentication_store_json',
        'pref_last_server_id',
        'pref_last_user_id',
        'last_playback_session',
        'pending_ratings_v1',
        'window_width',
        'device_capability_codec',
        'seerr_token_u1',
      ]) {
        expect(SettingsTransfer.resets(key), isFalse, reason: key);
      }
    });

    test('removes only what resets', () async {
      final prefs = await _prefs({
        'device_id': 'shield',
        'pref_last_user_id': 'u1',
        'home_sections_config': '[]',
        'hardware_decoding': false,
      });

      expect(await SettingsTransfer.reset(prefs), 2);
      expect(prefs.getKeys(), {'device_id', 'pref_last_user_id'});
    });
  });

  test('a snapshot can\'t sneak a device key in', () async {
    final prefs = await _prefs({'device_id': 'windows'});
    await SettingsTransfer.apply(prefs, {
      'format': SettingsTransfer.formatVersion,
      'values': {
        'device_id': ['s', 'shield'],
      },
    });
    expect(prefs.getString('device_id'), 'windows');
  });

  // Exported before the app was renamed: its own settings carried the old
  // name and land under the new one.
  test('a snapshot from before the rename lands under the new names', () async {
    final prefs = await _prefs({});
    await SettingsTransfer.apply(prefs, {
      'format': SettingsTransfer.formatVersion,
      'values': {
        'pref_plexfin_library_nicknames': ['s', '{"a":"Films"}'],
      },
    });
    expect(prefs.getString('pref_sunfin_library_nicknames'), '{"a":"Films"}');
    expect(prefs.containsKey('pref_plexfin_library_nicknames'), isFalse);
  });
}
