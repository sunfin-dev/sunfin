import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/admin/admin_access.dart';
import 'package:moonfin/util/platform_detection.dart';

void main() {
  tearDown(() {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    PlatformDetection.setTvMode(false);
    debugDefaultTargetPlatformOverride = null;
  });

  test('administrators get it on a PC, the TV look included', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);

    expect(adminAreaOffered(isAdministrator: true, kidsMode: false), isTrue);
    expect(adminAreaOffered(isAdministrator: false, kidsMode: false), isFalse);
    expect(adminAreaOffered(isAdministrator: true, kidsMode: true), isFalse);
  });

  test('a TV driven by a remote alone never offers it', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    PlatformDetection.setTvMode(true);

    expect(adminAreaOffered(isAdministrator: true, kidsMode: false), isFalse);
  });
}
