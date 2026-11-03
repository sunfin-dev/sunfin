import 'dart:convert';

import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart' show serverResponseRewriter;

/// Sunfin: the user's own names for their libraries, e.g. "4K Movies" for a
/// server library called "movies_4k".
///
/// Display only: nothing is renamed on the server. The names are applied to
/// every server answer as it arrives ([install]), so the sidebar, library
/// pages, "Recently Added in …" rows and settings all show them without each
/// screen knowing. Kept on this device only.
class LibraryNicknames {
  LibraryNicknames._();

  static final preference = Preference(
    key: 'pref_sunfin_library_nicknames',
    defaultValue: '{}',
  );

  /// Library item types a nickname applies to.
  static const _libraryTypes = {'CollectionFolder', 'UserView'};

  static PreferenceStore? _store;

  /// Library id -> (nickname, the server's name when it was set).
  static Map<String, ({String nickname, String serverName})> _entries = {};

  /// Loads the saved names and starts applying them to server answers.
  static void install(PreferenceStore store) {
    _store = store;
    _entries = _decode(store.get(preference));
    serverResponseRewriter = rewrite;
  }

  static String? nicknameFor(String libraryId) => _entries[libraryId]?.nickname;

  /// The server's own name for a nicknamed library, as it was when the
  /// nickname was given.
  static String? serverNameFor(String libraryId) =>
      _entries[libraryId]?.serverName;

  /// Sets or, with an empty [nickname], clears a library's nickname.
  /// [serverName] is the library's name on the server.
  static Future<void> set(
    String libraryId, {
    required String nickname,
    required String serverName,
  }) async {
    final trimmed = nickname.trim();
    final next = Map.of(_entries);
    if (trimmed.isEmpty || trimmed == serverName) {
      next.remove(libraryId);
    } else {
      next[libraryId] = (nickname: trimmed, serverName: serverName);
    }
    _entries = next;
    await _store?.set(preference, _encode(next));
  }

  /// Renames nicknamed libraries in a decoded server answer: a list of items
  /// (`{"Items": [...]}`) or a single item.
  static void rewrite(Object? data) {
    if (_entries.isEmpty || data is! Map) return;
    final items = data['Items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map) _apply(item);
      }
    } else {
      _apply(data);
    }
  }

  static void _apply(Map item) {
    final id = item['Id'];
    if (id is! String) return;
    final entry = _entries[id];
    if (entry == null || !_libraryTypes.contains(item['Type'])) return;
    item['Name'] = entry.nickname;
  }

  static Map<String, ({String nickname, String serverName})> _decode(
    String json,
  ) {
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String &&
              value is Map &&
              value['nickname'] is String &&
              value['server'] is String)
            key: (
              nickname: value['nickname'] as String,
              serverName: value['server'] as String,
            ),
      };
    } catch (_) {
      return {};
    }
  }

  static String _encode(
    Map<String, ({String nickname, String serverName})> entries,
  ) => jsonEncode({
    for (final MapEntry(:key, :value) in entries.entries)
      key: {'nickname': value.nickname, 'server': value.serverName},
  });
}
