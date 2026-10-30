import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<CustomTVTextFieldState> pumpField(WidgetTester tester) async {
    final key = GlobalKey<CustomTVTextFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomTVTextField(
            key: key,
            controller: TextEditingController(),
            hint: 'Search...',
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  // The Windows build draws the TV fields; a click there must type straight
  // in with a caret, not bring the remote's on-screen keyboard.
  testWidgets('on a computer a click types straight in and the hint goes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final field = await pumpField(tester);
    expect(_hint(tester).style?.color, isNot(Colors.transparent));

    await tester.tap(find.byType(CustomTVTextField));
    // The field blinks forever once it has focus, so settle is not available.
    await tester.pump(const Duration(milliseconds: 100));

    expect(field.isTyping, isTrue);
    expect(find.byType(Dialog), findsNothing);
    expect(_hint(tester).style?.color, Colors.transparent);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on a TV a click still brings the on-screen keyboard', (
    tester,
  ) async {
    final field = await pumpField(tester);

    await tester.tap(find.byType(CustomTVTextField));
    await tester.pump(const Duration(milliseconds: 100));

    expect(field.isTyping, isFalse);
    expect(find.byType(Dialog), findsOneWidget);
    field.closeKeyboard(submit: false);
    await tester.pump(const Duration(milliseconds: 100));
  });
}

TextSpan _hint(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .expand((t) => _spans(t.text))
    .where((s) => s.text == 'Search...')
    .single;

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}
