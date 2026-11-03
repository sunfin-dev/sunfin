import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockSessionRepository extends Mock implements SessionRepository {}

class _MockSeerrRepository extends Mock implements SeerrRepository {}

/// A plugin that offers settings sync and a stored profile, and writes down
/// every request it gets.
class _PluginAdapter implements HttpClientAdapter {
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    requests.add('${options.method} $path');
    Map<String, dynamic>? body;
    if (path.endsWith('/Moonfin/Ping')) {
      body = {'installed': true, 'settingsSyncEnabled': true};
    } else if (path.contains('/Moonfin/Settings/Resolved/')) {
      body = {'homeRowOrder': ['smalllibrarytiles', 'resume']};
    }
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Sunfin: settings move only through Transfer settings (user,
/// 2026-10-28), so on TV the plugin's settings profile is never read or
/// written on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PluginSyncService service;
  late _MockClient client;
  late _PluginAdapter adapter;
  late UserPreferences prefs;

  bool touchedProfile() => adapter.requests.any(
    (r) => r.contains('/Moonfin/Settings/Resolved/') ||
        r.contains('/Moonfin/Settings/Profile/') ||
        r.contains('/Moonfin/Settings/Stream'),
  );

  Future<void> setUpWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues({
      'pref_last_server_id': 'srv1',
      ...stored,
    });
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);

    final session = _MockSessionRepository();
    when(() => session.activeUserId).thenReturn('user1');
    GetIt.instance.registerSingleton<SeerrPreferences>(
      SeerrPreferences(store, session),
    );

    client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://plugin.test');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'dev1',
        name: 'test',
        appName: 'moonfin',
        appVersion: '0.0.0',
      ),
    );
    GetIt.instance.registerSingleton<MediaServerClient>(client);

    final seerr = _MockSeerrRepository();
    when(
      () => seerr.ensureInitialized(force: any(named: 'force')),
    ).thenAnswer((_) async {});
    when(() => seerr.isAvailable).thenReturn(false);
    GetIt.instance.registerLazySingletonAsync<SeerrRepository>(
      () async => seerr,
    );

    adapter = _PluginAdapter();
    service = PluginSyncService(prefs, store, dio: Dio()..httpClientAdapter = adapter);
  }

  setUp(() => PlatformDetection.setTvMode(true));

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  test('a first sign-in leaves the server profile alone', () async {
    await setUpWith({});

    await service.syncOnLogin(client, serverId: 'srv1');

    expect(await service.refreshAvailability(client), isTrue);
    expect(touchedProfile(), isFalse, reason: adapter.requests.join('\n'));
    expect(prefs.get(UserPreferences.homeSectionsJson), isEmpty);
  });

  test('a device that synced before stops reading the profile', () async {
    // What an older build left behind: sync switched on and done once.
    await setUpWith({
      'pref_plugin_sync_enabled': true,
      'pref_plugin_sync_initialized_srv1': true,
    });

    await service.syncOnLogin(client, serverId: 'srv1');
    await service.pushSettings(client, force: true);

    expect(touchedProfile(), isFalse, reason: adapter.requests.join('\n'));
  });
}
