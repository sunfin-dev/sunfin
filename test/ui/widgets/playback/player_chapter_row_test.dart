import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/playback/player_chapter_row.dart';
import 'package:server_core/server_core.dart';

class _MockImageApi extends Mock implements ImageApi {}

Map<String, dynamic> _chapter(String name, Duration start) => {
  'Name': name,
  'StartPositionTicks': start.inMicroseconds * 10,
};

void main() {
  final chapters = [
    _chapter('Intro', Duration.zero),
    _chapter('Act One', const Duration(minutes: 2)),
    _chapter('Act Two', const Duration(minutes: 20)),
  ];

  test('opens on the chapter playback is in', () {
    expect(PlayerChapterRow.chapterAt(chapters, Duration.zero), 0);
    expect(
      PlayerChapterRow.chapterAt(chapters, const Duration(minutes: 5)),
      1,
    );
    expect(
      PlayerChapterRow.chapterAt(chapters, const Duration(hours: 1)),
      2,
    );
  });

  Future<({List<Duration> picked, List<String> left})> pumpRow(
    WidgetTester tester, {
    Duration position = Duration.zero,
  }) async {
    final imageApi = _MockImageApi();
    when(
      () => imageApi.getChapterImageUrl(
        any(),
        index: any(named: 'index'),
        maxWidth: any(named: 'maxWidth'),
        tag: any(named: 'tag'),
      ),
    ).thenReturn('');
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final picked = <Duration>[];
    final left = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlayerChapterRow(
            chapters: chapters,
            itemId: 'item',
            imageApi: imageApi,
            position: position,
            focusNode: focusNode,
            onPick: picked.add,
            onLeave: () => left.add('leave'),
            onActivity: () {},
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    return (picked: picked, left: left);
  }

  testWidgets('right then OK jumps to the next chapter', (tester) async {
    final calls = await pumpRow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(calls.picked, [const Duration(minutes: 2)]);
  });

  testWidgets('left stops at the first chapter', (tester) async {
    final calls = await pumpRow(tester, position: const Duration(minutes: 3));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(calls.picked, [Duration.zero]);
  });

  testWidgets('up leaves the row without jumping', (tester) async {
    final calls = await pumpRow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(calls.left, ['leave']);
    expect(calls.picked, isEmpty);
  });
}
