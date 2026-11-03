import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The fonts bundled in assets/fonts, keyed by the license file that has to
/// travel with them. The SIL Open Font License asks for its text to ship with
/// the font, so each one is shown on the licenses screen.
const Map<String, String> _fontLicenseFiles = {
  'Roboto': 'assets/fonts/Roboto-LICENSE.txt',
  'Noto Sans': 'assets/licenses/fonts/NotoSans.txt',
  'Noto Sans CJK': 'assets/licenses/fonts/NotoSansCJK.txt',
  'Orbitron': 'assets/licenses/fonts/Orbitron.txt',
  'Press Start 2P': 'assets/licenses/fonts/PressStart2P.txt',
  'Rajdhani': 'assets/licenses/fonts/Rajdhani.txt',
};

/// Adds the bundled fonts to LicenseRegistry. A missing file is skipped.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: font, value: path) in _fontLicenseFiles.entries) {
      final String text;
      try {
        text = await rootBundle.loadString(path);
      } catch (_) {
        continue;
      }
      yield LicenseEntryWithLineBreaks(['$font (font)'], text);
    }
  });
}
