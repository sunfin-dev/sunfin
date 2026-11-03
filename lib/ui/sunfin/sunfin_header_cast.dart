import 'dart:async';

import 'package:get_it/get_it.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/services/media_server_client_factory.dart';

/// Top-billed cast for the Sunfin home header.
///
/// Home rows don't ask Jellyfin for People: a full cast list on every row
/// item would slow each home load on the Shield. Instead the header asks for
/// the one item focus settles on, once, and keeps the answer.
abstract final class SunfinHeaderCast {
  static const _maxEntries = 100;
  static const _maxNames = 3;

  // Insertion-ordered, so the first key is the least recently used.
  static final _cache = <String, List<String>>{};
  static final _pending = <String, Future<List<String>>>{};

  static String _key(AggregatedItem item) => '${item.serverId}|${item.id}';

  static List<String>? cached(AggregatedItem item) {
    final key = _key(item);
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit;
    return hit;
  }

  static Future<List<String>> resolve(AggregatedItem item) {
    final hit = cached(item);
    if (hit != null) return Future.value(hit);
    final key = _key(item);
    // A block body on purpose: `=> _pending.remove(key)` would hand
    // whenComplete this very future to wait for, and it never completed.
    return _pending[key] ??= _fetch(item, key).whenComplete(() {
      _pending.remove(key);
    });
  }

  static Future<List<String>> _fetch(AggregatedItem item, String key) async {
    try {
      final client = GetIt.instance<MediaServerClientFactory>()
          .clientForServerOrActive(item.serverId);
      final response = await client.itemsApi.getItems(
        ids: [item.id],
        fields: 'People',
      );
      final items = response['Items'] as List? ?? const [];
      final people = items.isEmpty
          ? const []
          : ((items.first as Map)['People'] as List? ?? const []);
      final names = <String>[];
      for (final person in people) {
        if (person is! Map || person['Type'] != 'Actor') continue;
        final name = person['Name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        names.add(name);
        if (names.length == _maxNames) break;
      }
      _cache[key] = names;
      if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
      return names;
    } catch (_) {
      // Not cached: a dropped connection shouldn't hide the cast for good.
      return const [];
    }
  }
}
