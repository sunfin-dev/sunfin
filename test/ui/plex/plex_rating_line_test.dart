import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/plex/plex_detail_parts.dart';
import 'package:moonfin/ui/plex/plex_movie_page.dart';
import 'package:moonfin/ui/plex/plex_rating_line.dart';
import 'package:shared_preferences/shared_preferences.dart';

AggregatedItem _movie({double? community, int? critic, double? mine}) =>
    AggregatedItem(
      id: 'm1',
      serverId: 's1',
      rawData: {
        'Id': 'm1',
        'Name': 'Interstellar',
        'Type': 'Movie',
        'CommunityRating': ?community,
        'CriticRating': ?critic,
        'UserData': {'Rating': ?mine},
      },
    );

void main() {
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
  });

  Future<void> pump(WidgetTester tester, AggregatedItem item) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlexRatingLine(item: item, extraRatings: const {}, prefs: prefs),
          ),
        ),
      );

  Iterable<Icon> stars(WidgetTester tester) => tester
      .widgetList<Icon>(find.byType(Icon))
      .where((i) => i.icon == Symbols.star || i.icon == Symbols.star_half)
      .skip(1);

  testWidgets('the community score reads as a percentage, as in Plex', (
    tester,
  ) async {
    await pump(tester, _movie(community: 8.4, critic: 73));

    expect(find.text('84%'), findsOneWidget);
    expect(find.text('73%'), findsOneWidget);
  });

  testWidgets('five hollow stars until the viewer rates', (tester) async {
    await pump(tester, _movie(community: 8.4));

    final row = stars(tester).toList();
    expect(row, hasLength(5));
    expect(row.every((s) => s.fill == 0), isTrue);
  });

  testWidgets('a 7 out of 10 fills three and a half stars', (tester) async {
    await pump(tester, _movie(community: 8.4, mine: 7));

    final row = stars(tester).toList();
    expect(row.where((s) => s.fill == 1), hasLength(4));
    expect(row[3].icon, Symbols.star_half);
    expect(row[4].fill, 0);
  });

  test('Kids Mode shows no rating line', () async {
    await prefs.set(UserPreferences.kidsModeEnabled, true);
    expect(
      PlexRatingLine.of(item: _movie(), extraRatings: const {}, prefs: prefs),
      isNull,
    );
  });

  test('the memo keeps a part while its inputs hold the same entries', () {
    final cast = [
      {'Name': 'A'},
    ];
    expect(PlexMemo.sameInputs([1, cast], [1, List.of(cast)]), isTrue);
    expect(
      PlexMemo.sameInputs(
        [1, cast],
        [
          1,
          [
            {'Name': 'A'},
          ],
        ],
      ),
      isFalse,
    );
    expect(PlexMemo.sameInputs([1], [2]), isFalse);
  });

  test('movies and videos open the movie page', () {
    AggregatedItem of(String type) => AggregatedItem(
      id: 'x',
      serverId: 's',
      rawData: {'Id': 'x', 'Type': type},
    );
    expect(PlexMoviePage.handles(of('Movie')), isTrue);
    expect(PlexMoviePage.handles(of('Video')), isTrue);
    expect(PlexMoviePage.handles(of('Series')), isFalse);
    expect(PlexMoviePage.handles(of('Episode')), isFalse);
  });
}
