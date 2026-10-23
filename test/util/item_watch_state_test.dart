import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/util/item_watch_state.dart';

AggregatedItem _item(String type, Map<String, dynamic> extra) => AggregatedItem(
  id: 'i1',
  serverId: 's1',
  rawData: {'Id': 'i1', 'Type': type, ...extra},
);

void main() {
  group('cardProgressOf', () {
    test('a movie part way through keeps its bar', () {
      final item = _item('Movie', {
        'UserData': {'PlayedPercentage': 40.0},
      });
      expect(cardProgressOf(item), 40.0);
    });

    test('a finished show draws no bar, as in Plex', () {
      final item = _item('Series', {
        'UserData': {'PlayedPercentage': 100.0, 'Played': true},
      });
      expect(cardProgressOf(item), isNull);
    });

    test('a part watched season or collection draws no bar', () {
      for (final type in ['Season', 'BoxSet']) {
        final item = _item(type, {
          'UserData': {'PlayedPercentage': 55.0},
        });
        expect(cardProgressOf(item), isNull, reason: type);
      }
    });
  });

  group('a plain item', () {
    test('with nothing watched has no progress', () {
      final ws = watchStateOf(_item('Movie', {}));
      expect(ws.hasProgress, isFalse);
      expect(ws.isFullyUnwatched, isTrue);
      expect(ws.isFullyWatched, isFalse);
    });

    test('with a resume position has progress', () {
      final ws = watchStateOf(
        _item('Movie', {
          'UserData': {'PlaybackPositionTicks': 6000000000},
        }),
      );
      expect(ws.hasProgress, isTrue);
      expect(ws.isPartiallyWatched, isTrue);
      expect(ws.isFullyUnwatched, isFalse);
    });

    test('with a played percentage has progress', () {
      final ws = watchStateOf(
        _item('Episode', {
          'UserData': {'PlayedPercentage': 12.5},
        }),
      );
      expect(ws.hasProgress, isTrue);
    });

    test('marked played reads as fully watched', () {
      final ws = watchStateOf(
        _item('Movie', {
          'UserData': {'Played': true},
        }),
      );
      expect(ws.isFullyWatched, isTrue);
      expect(ws.isFullyUnwatched, isFalse);
    });
  });

  group('a series', () {
    test('nobody has started is fully unwatched', () {
      final ws = watchStateOf(
        _item('Series', {
          'RecursiveItemCount': 10,
          'UserData': {'UnplayedItemCount': 10},
        }),
      );
      expect(ws.isFullyUnwatched, isTrue);
      expect(ws.hasProgress, isFalse);
    });

    test('part way through has progress even with no position of its own', () {
      final ws = watchStateOf(
        _item('Series', {
          'RecursiveItemCount': 10,
          'UserData': {'UnplayedItemCount': 4},
        }),
      );
      expect(ws.isPartiallyWatched, isTrue);
      expect(ws.hasProgress, isTrue);
    });

    test('with nothing left unplayed is fully watched', () {
      final ws = watchStateOf(
        _item('Series', {
          'RecursiveItemCount': 10,
          'UserData': {'UnplayedItemCount': 0},
        }),
      );
      expect(ws.isFullyWatched, isTrue);
      expect(ws.hasProgress, isFalse);
    });
  });

  group('a season', () {
    test('answers progress from its own position, not its child count', () {
      final counted = watchStateOf(
        _item('Season', {
          'ChildCount': 10,
          'UserData': {'UnplayedItemCount': 4},
        }),
      );
      expect(counted.isPartiallyWatched, isTrue);
      expect(
        counted.hasProgress,
        isFalse,
        reason: 'only a series stands in its children for progress',
      );

      final positioned = watchStateOf(
        _item('Season', {
          'ChildCount': 10,
          'UserData': {'UnplayedItemCount': 4, 'PlayedPercentage': 30.0},
        }),
      );
      expect(positioned.hasProgress, isTrue);
    });
  });
}
