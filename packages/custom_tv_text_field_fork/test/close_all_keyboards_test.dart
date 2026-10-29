import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('closing all keyboards closes every open one, unsubmitted', (
    tester,
  ) async {
    final keys = [
      GlobalKey<CustomTVTextFieldState>(),
      GlobalKey<CustomTVTextFieldState>(),
    ];
    var submitted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final key in keys)
                CustomTVTextField(
                  key: key,
                  controller: TextEditingController(),
                  onFieldSubmitted: (_) => submitted++,
                ),
            ],
          ),
        ),
      ),
    );
    for (final key in keys) {
      key.currentState!.openKeyboard();
      // The field blinks forever once it has focus, so settle is not available.
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(CustomTVTextField.isKeyboardVisibleNotifier.value, isTrue);

    CustomTVTextField.closeAllKeyboards();
    await tester.pump(const Duration(milliseconds: 50));

    expect(CustomTVTextField.isKeyboardVisibleNotifier.value, isFalse);
    expect(CustomTVTextField.closeTopKeyboard(), isFalse);
    expect(submitted, 0);
  });
}
