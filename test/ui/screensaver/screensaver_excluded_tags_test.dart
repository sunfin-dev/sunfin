import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screensaver/screensaver_content_service.dart';

void main() {
  test('an item with an excluded tag is left out, whatever its capitals', () {
    final item = {
      'Name': 'Something grim',
      'Tags': ['Gore', 'Revenge'],
    };
    expect(ScreensaverContentService.hasExcludedTag(item, {'gore'}), isTrue);
  });

  test('an item without one stays', () {
    final item = {
      'Name': 'Something gentle',
      'Tags': ['Family'],
    };
    expect(ScreensaverContentService.hasExcludedTag(item, {'gore'}), isFalse);
    expect(ScreensaverContentService.hasExcludedTag({'Name': 'No tags'}, {'gore'}), isFalse);
  });

  test('nothing is left out when no tag is excluded', () {
    expect(
      ScreensaverContentService.hasExcludedTag({'Tags': ['Gore']}, const {}),
      isFalse,
    );
  });
}
