import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/plex/plex_library_page.dart';
import 'package:moonfin/ui/plex/plex_poster.dart';
import 'package:moonfin/ui/screens/detail/nouveau/nouveau_detail_content.dart';

AggregatedItem _item(Map<String, dynamic> data) => AggregatedItem(
  id: data['Id'] as String? ?? 'x',
  serverId: 's',
  rawData: {'Id': 'x', ...data},
);

String _count(int count) => '$count items';

void main() {
  group('the letter a library title files under', () {
    test('is its sort name\'s first letter', () {
      final item = _item({'Name': 'The Matrix', 'SortName': 'Matrix'});
      expect(plexLibraryLetter(item), 'M');
    });

    test('ignores accents', () {
      expect(plexLibraryLetter(_item({'Name': 'Ángel'})), 'A');
    });

    test('is # for digits and symbols', () {
      expect(plexLibraryLetter(_item({'Name': '2001'})), '#');
      expect(plexLibraryLetter(_item({'Name': '(500) Days'})), '#');
    });

    test('is nothing without a name', () {
      expect(plexLibraryLetter(_item({'Name': ''})), isNull);
    });
  });

  group('library card captions', () {
    test('a movie shows its title and year', () {
      final item = _item({
        'Name': 'Zodiac',
        'Type': 'Movie',
        'ProductionYear': 2007,
      });
      expect(plexLibraryCaptions(item, itemCount: _count), ('Zodiac', '2007'));
    });

    test('an episode shows its show and number', () {
      final item = _item({
        'Name': 'Red Scale',
        'Type': 'Episode',
        'SeriesName': 'Jujutsu Kaisen',
        'ParentIndexNumber': 2,
        'IndexNumber': 13,
      });
      expect(plexLibraryCaptions(item, itemCount: _count), (
        'Jujutsu Kaisen',
        'S2 · E13',
      ));
    });

    test('a season shows its show and its own name', () {
      final item = _item({
        'Name': 'Season 1',
        'Type': 'Season',
        'SeriesName': 'The Bear',
      });
      expect(plexLibraryCaptions(item, itemCount: _count), (
        'The Bear',
        'Season 1',
      ));
    });

    test('an album shows its artist', () {
      final item = _item({
        'Name': 'Blue',
        'Type': 'MusicAlbum',
        'AlbumArtist': 'Joni Mitchell',
      });
      expect(plexLibraryCaptions(item, itemCount: _count), (
        'Blue',
        'Joni Mitchell',
      ));
    });

    test('a collection counts its titles', () {
      final item = _item({'Name': 'Alien', 'Type': 'BoxSet', 'ChildCount': 4});
      expect(plexLibraryCaptions(item, itemCount: _count), (
        'Alien',
        '4 items',
      ));
    });
  });

  group('details section inputs', () {
    test('are the same for the same values', () {
      final item = Object();
      expect(
        nouveauSameSectionInputs(
          [item, const EdgeInsets.all(4)],
          [item, const EdgeInsets.all(4)],
        ),
        isTrue,
      );
    });

    test('are the same for a fresh list of the same entries', () {
      final actor = {'Name': 'A'};
      expect(
        nouveauSameSectionInputs(
          [
            [actor],
          ],
          [
            [actor],
          ],
        ),
        isTrue,
      );
    });

    test('differ once an entry is replaced', () {
      expect(
        nouveauSameSectionInputs(
          [
            [
              {'Name': 'A'},
            ],
          ],
          [
            [
              {'Name': 'A'},
            ],
          ],
        ),
        isFalse,
      );
    });

    test('differ when one input changes', () {
      expect(nouveauSameSectionInputs([1, 2], [1, 3]), isFalse);
      expect(nouveauSameSectionInputs([1], [1, 2]), isFalse);
    });
  });

  group('library poster card', () {
    Future<FocusNode> pump(
      WidgetTester tester,
      AggregatedItem item, {
      bool showCaptions = true,
      VoidCallback? onTap,
    }) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: PlexPosterCard(
              item: item,
              imageUrl: null,
              width: 120,
              aspectRatio: 2 / 3,
              title: item.name,
              subtitle: '2025',
              showCaptions: showCaptions,
              focusNode: node,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      );
      return node;
    }

    testWidgets('shows a show\'s unwatched episodes in the corner', (
      tester,
    ) async {
      await pump(
        tester,
        _item({
          'Name': 'Rooster',
          'Type': 'Series',
          'UserData': {'UnplayedItemCount': 10, 'Played': false},
        }),
      );
      expect(find.byType(PlexCornerBadge), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('ticks a watched movie', (tester) async {
      await pump(
        tester,
        _item({
          'Name': 'Whiplash',
          'Type': 'Movie',
          'UserData': {'Played': true},
        }),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('leaves an unwatched movie bare', (tester) async {
      await pump(tester, _item({'Name': 'Zodiac', 'Type': 'Movie'}));
      expect(find.byType(PlexCornerBadge), findsNothing);
    });

    testWidgets('can leave the captions out', (tester) async {
      await pump(
        tester,
        _item({'Name': 'Zodiac', 'Type': 'Movie'}),
        showCaptions: false,
      );
      // The title still names a poster with no artwork.
      expect(find.text('2025'), findsNothing);
    });

    testWidgets('opens on OK once focused', (tester) async {
      var taps = 0;
      final node = await pump(
        tester,
        _item({'Name': 'Zodiac', 'Type': 'Movie'}),
        onTap: () => taps++,
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(taps, 1);
    });
  });
}
