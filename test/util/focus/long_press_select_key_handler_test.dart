import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/focus/key_event_utils.dart';

KeyEvent _select(Type type) {
  const physical = PhysicalKeyboardKey.select;
  const logical = LogicalKeyboardKey.select;
  final stamp = Duration.zero;
  return switch (type) {
    const (KeyDownEvent) => KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: stamp,
    ),
    const (KeyRepeatEvent) => KeyRepeatEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: stamp,
    ),
    _ => KeyUpEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: stamp,
    ),
  };
}

void main() {
  late List<String> calls;
  late LongPressSelectKeyHandler handler;

  setUp(() {
    calls = [];
    handler = LongPressSelectKeyHandler();
  });
  tearDown(() => handler.dispose());

  void send(Type type) => handler.handleKeyEvent(
    _select(type),
    onTap: () => calls.add('tap'),
    onLongPress: () => calls.add('hold'),
  );

  test('a quick press is a tap, on release', () {
    fakeAsync((async) {
      send(KeyDownEvent);
      async.elapse(const Duration(milliseconds: 100));
      expect(calls, isEmpty);
      send(KeyUpEvent);
      expect(calls, ['tap']);
    });
  });

  test('held past the timer it is a hold, and release does nothing more', () {
    fakeAsync((async) {
      send(KeyDownEvent);
      async.elapse(const Duration(milliseconds: 600));
      send(KeyUpEvent);
      expect(calls, ['hold']);
    });
  });

  // Android marks a press long on its first repeat, before the timer; adb's
  // long press releases right after it.
  test('the first repeat is a hold too, once', () {
    fakeAsync((async) {
      send(KeyDownEvent);
      async.elapse(const Duration(milliseconds: 400));
      send(KeyRepeatEvent);
      send(KeyRepeatEvent);
      async.elapse(const Duration(milliseconds: 300));
      send(KeyUpEvent);
      expect(calls, ['hold']);
    });
  });
}
