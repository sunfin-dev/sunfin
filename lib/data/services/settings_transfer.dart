import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plexfin: copies every setting from one device to another through the
/// user's own Jellyfin account (user, 2026-10-27: "copy all of my settings
/// from my shield to the windows build").
///
/// Export saves a snapshot of the app's stored settings in the account's
/// display preferences, which every Jellyfin server keeps per user with no
/// plugin; import on the other device, signed in to the same account, loads
/// it. Every stored key travels unless it belongs to this device, so a
/// setting added later travels without being listed here.
///
/// Logins never travel: each device signs in on its own (Quick Connect), and
/// the snapshot would otherwise be a working key to the account.
abstract final class SettingsTransfer {
  /// Where the snapshot lives in the account's display preferences.
  static const displayPreferencesId = 'plexfin-settings-transfer';
  static const client = 'plexfin';

  /// 2: setting names carry [_serverToken] and [_userToken] instead of the
  /// exporting device's ids. Version 1 snapshots kept them, so their
  /// per-account settings landed where no other device looks.
  static const formatVersion = 2;

  /// Most settings are stored per account, under a name ending in this
  /// app's id for the server entry and the user's id (UserPreferences). The
  /// server entry's id is made up by each device, so the snapshot names the
  /// account with these tokens and import puts its own ids back in.
  static const _serverToken = '{server}';
  static const _userToken = '{user}';
  static const _serverIdKey = 'pref_last_server_id';
  static const _userIdKey = 'pref_last_user_id';

  static (String, String)? _account(SharedPreferences prefs) {
    final server = (prefs.getString(_serverIdKey) ?? '').trim();
    final user = (prefs.getString(_userIdKey) ?? '').trim();
    return server.isEmpty || user.isEmpty ? null : (server, user);
  }

  /// [key] with the signed-in account's ids as tokens.
  static String _toTokens(String key, (String, String)? account) {
    if (account == null) return key;
    final (server, user) = account;
    return key.replaceAll(server, _serverToken).replaceAll(user, _userToken);
  }

  /// [key] for the account signed in here, or null when it names an
  /// account and nobody is signed in.
  static String? _fromTokens(String key, (String, String)? account) {
    if (!key.contains(_serverToken) && !key.contains(_userToken)) return key;
    if (account == null) return null;
    final (server, user) = account;
    return key.replaceAll(_serverToken, server).replaceAll(_userToken, user);
  }

  /// Display preference values are stored one per row on the server, so a
  /// large snapshot is split over several.
  @visibleForTesting
  static const chunkLength = 16000;

  /// Keys that describe this device rather than the user's choices: its
  /// identity and sign-in, its window, what its hardware can do and how its
  /// outputs are wired, and its own caches and timers.
  static const _deviceKeys = {
    'device_id',
    'authentication_store_json',
    'pref_last_server_id',
    'pref_last_user_id',
    'last_playback_session',
    'pending_crash_reports',
    'pending_ratings_v1',
    'pref_interface_layout',
    'pref_performance_mode',
    'pref_desktop_ui_scale',
    'pref_use_hardware_rendering',
    'hardware_decoding',
    'external_player',
    'external_player_component',
    'refresh_rate_switching_behavior',
    'auto_hdr_switching_behavior',
    'native_hdr_output',
    'media3_tunneling_disabled',
    'tunneling_fallback_disabled',
    'pref_audio_passthrough_mode',
    'pref_audio_passthrough_output',
    'audio_fallback_codec',
    'player_volume',
    'image_cache_limit_mb',
    'download_storage_limit_mb',
    'download_custom_path',
    'download_custom_path_bookmark',
    'auto_download_last_run',
    'auto_download_storage_notice_shown',
  };

  static const _devicePrefixes = [
    'window_',
    'device_capability_',
    'pref_passthrough_',
    'last_',
  ];

  /// Sign-ins of any service: the Jellyfin token itself is in secure
  /// storage, but nothing that looks like one may leave the device.
  static final _login = RegExp(
    'token|cookie|password|session',
    caseSensitive: false,
  );

  /// Whether [key] goes from one device to another.
  static bool travels(String key) {
    if (_deviceKeys.contains(key)) return false;
    if (_devicePrefixes.any(key.startsWith)) return false;
    return !_login.hasMatch(key);
  }

  /// What a reset leaves alone: who this device is and who is signed in,
  /// plus what was recorded rather than chosen (window, detected hardware,
  /// timers, queued reports and ratings). This device's own settings, its
  /// hardware ones included, do go back.
  static const _keptOnResetKeys = {
    'device_id',
    'authentication_store_json',
    'pref_last_server_id',
    'pref_last_user_id',
    'last_playback_session',
    'pending_crash_reports',
    'pending_ratings_v1',
  };

  static const _keptOnResetPrefixes = [
    'window_',
    'device_capability_',
    'last_',
  ];

  /// Whether a reset puts [key] back to its default.
  @visibleForTesting
  static bool resets(String key) {
    if (_keptOnResetKeys.contains(key)) return false;
    if (_keptOnResetPrefixes.any(key.startsWith)) return false;
    return !_login.hasMatch(key);
  }

  /// Plexfin: puts every setting on this device back to its default (user,
  /// 2026-10-28). Only this device: a snapshot exported to the account
  /// stays there to import later. Returns how many settings went back.
  static Future<int> reset(SharedPreferences prefs) async {
    var removed = 0;
    for (final key in prefs.getKeys().toList()) {
      if (resets(key) && await prefs.remove(key)) removed++;
    }
    return removed;
  }

  /// Every travelling setting in [prefs], with its type, so an int stays an
  /// int where JSON would not tell it from a double.
  static Map<String, Object?> snapshot(
    SharedPreferences prefs, {
    required String device,
    DateTime? now,
  }) {
    final values = <String, List<Object?>>{};
    final account = _account(prefs);
    for (final key in prefs.getKeys().toList()..sort()) {
      if (!travels(key)) continue;
      final value = prefs.get(key);
      final type = switch (value) {
        bool _ => 'b',
        int _ => 'i',
        double _ => 'd',
        String _ => 's',
        List _ => 'l',
        _ => null,
      };
      if (type != null) values[_toTokens(key, account)] = [type, value];
    }
    return {
      'format': formatVersion,
      'device': device,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'values': values,
    };
  }

  /// [snapshot] as display preference values.
  static Map<String, String> encode(Map<String, Object?> snapshot) {
    final json = jsonEncode(snapshot);
    final parts = <String, String>{};
    var count = 0;
    for (var i = 0; i < json.length; i += chunkLength) {
      final end = i + chunkLength < json.length ? i + chunkLength : json.length;
      parts['part$count'] = json.substring(i, end);
      count++;
    }
    return {'parts': '$count', ...parts};
  }

  /// The snapshot stored in [customPrefs], or null when there is none or it
  /// can't be read.
  static Map<String, Object?>? decode(Map<String, String> customPrefs) {
    final count = int.tryParse(customPrefs['parts'] ?? '');
    if (count == null || count < 1) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      final part = customPrefs['part$i'];
      if (part == null) return null;
      buffer.write(part);
    }
    try {
      final snapshot = jsonDecode(buffer.toString());
      if (snapshot is! Map<String, Object?>) return null;
      if (snapshot['format'] != formatVersion) return null;
      if (snapshot['values'] is! Map) return null;
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  /// Makes this device's settings match [snapshot]: every setting in it is
  /// written, and a setting of this device's that it doesn't have goes back
  /// to its default. What belongs to this device is left alone. Returns how
  /// many settings were written.
  static Future<int> apply(
    SharedPreferences prefs,
    Map<String, Object?> snapshot,
  ) async {
    final account = _account(prefs);
    final values = <String, Object?>{
      for (final MapEntry(:key, :value)
          in (snapshot['values'] as Map).cast<String, Object?>().entries)
        ?_fromTokens(key, account): value,
    };
    for (final key in prefs.getKeys().toList()) {
      if (travels(key) && !values.containsKey(key)) await prefs.remove(key);
    }
    var written = 0;
    for (final MapEntry(:key, :value) in values.entries) {
      if (!travels(key) || value is! List || value.length != 2) continue;
      final data = value[1];
      final ok = switch (value[0]) {
        'b' when data is bool => await prefs.setBool(key, data),
        'i' when data is num => await prefs.setInt(key, data.toInt()),
        'd' when data is num => await prefs.setDouble(key, data.toDouble()),
        's' when data is String => await prefs.setString(key, data),
        'l' when data is List => await prefs.setStringList(
          key,
          data.map((e) => '$e').toList(),
        ),
        _ => false,
      };
      if (ok) written++;
    }
    return written;
  }

  /// Saves this device's settings to the signed-in account. Returns how
  /// many settings went.
  static Future<int> export(
    DisplayPreferencesApi api, {
    required String device,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = snapshot(prefs, device: device);
    await api.saveDisplayPreferences(
      displayPreferencesId,
      DisplayPreferences(id: displayPreferencesId, customPrefs: encode(data)),
      client: client,
    );
    return (data['values'] as Map).length;
  }

  /// The snapshot saved in the signed-in account, or null when there is
  /// none.
  static Future<Map<String, Object?>?> fetch(DisplayPreferencesApi api) async {
    final stored = await api.getDisplayPreferences(
      displayPreferencesId,
      client: client,
    );
    return decode(stored.customPrefs);
  }
}
