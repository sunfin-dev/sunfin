import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/sunfin/sunfin_home_header.dart';

AggregatedItem _movie(String overview) => AggregatedItem(
  id: 'm1',
  serverId: 's1',
  rawData: {
    'Id': 'm1',
    'Name': 'Interstellar',
    'Type': 'Movie',
    'ProductionYear': 2014,
    'Genres': ['Adventure', 'Drama', 'Science Fiction'],
    'Overview': overview,
  },
);

void main() {
  Future<void> pump(WidgetTester tester, String overview) async {
    tester.view.physicalSize = const Size(1150, 647);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SunfinHomeHeader(
                item: _movie(overview),
                leftInset: 20,
                showCast: false,
                height: 320,
                grow: true,
                ratingLine: const SizedBox(height: 14, width: 80),
                footer: 'Directed by Christopher Nolan',
              ),
              const SizedBox(key: ValueKey('below'), height: 10, width: 10),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a long summary pushes what follows down rather than cutting '
      '"Directed by"', (tester) async {
    await pump(tester, 'A very long summary that goes on and on. ' * 20);

    final footer = tester.getRect(find.text('Directed by Christopher Nolan'));
    final below = tester.getRect(find.byKey(const ValueKey('below')));
    expect(below.top, greaterThanOrEqualTo(footer.bottom));
  });

  testWidgets('a short summary keeps the header at its usual height', (
    tester,
  ) async {
    await pump(tester, 'Short.');

    final below = tester.getRect(find.byKey(const ValueKey('below')));
    expect(below.top, 320);
  });
}
