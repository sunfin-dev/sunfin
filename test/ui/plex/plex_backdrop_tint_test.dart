import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/plex/plex_backdrop_tint.dart';

/// A 16x9 RGBA sample from rows of 16 'rrggbb' hex pixels.
ByteData sample(List<String> rows) {
  final bytes = Uint8List(16 * 9 * 4);
  var i = 0;
  for (final row in rows) {
    for (final px in row.trim().split(RegExp(r'\s+'))) {
      final v = int.parse(px, radix: 16);
      bytes[i++] = v >> 16 & 255;
      bytes[i++] = v >> 8 & 255;
      bytes[i++] = v & 255;
      bytes[i++] = 255;
    }
  }
  return ByteData.sublistView(bytes);
}

/// The Bear's series backdrop as the server sends it at sample size: a dark
/// brown frame around a night-sky city, the cast in red, skin and wood tones.
final theBear = sample([
  '1e1916 201a18 201a17 201a18 201a17 201a18 201a18 241c1a 281f1d 28201e 2a211f 29211f 29211f 2a211f 2a2220 28201e',
  '1e1815 272531 292531 272735 212636 1d2335 21293e 533d33 5d4135 262b40 282c43 2b2c42 2c2c42 292941 372f3a 29201d',
  '1e1714 3c3a3f 34333c 30394b 32323e 50555e 77685f 92735f 795345 2f4365 5f5053 464d5e 434d62 4c5262 483d41 28201d',
  '1f1613 504642 48484c 38414d 594340 614e45 6c5143 99866f 806658 909787 805f57 7a655e 69554e 858179 6f6156 271f1c',
  '1e1614 4d4038 534148 5f372f 9f6147 942227 3f3937 4a484e 625452 4e4140 b4aa8d 494c44 41443c 7c6053 594c47 261f1c',
  '1c1614 7d6a51 4e3c3b 5e4c40 6d463c 852a28 89836e 694f48 6a514d 746354 b09f84 483832 503138 6d3847 5e4137 2a211f',
  '1e1714 433432 62493d 61413b 88292d 926556 afae8e 7f5b41 5f402d c7c09e b9ae90 393534 463c39 523f33 6d4940 332723',
  '211613 332721 4d3d31 3e2922 4c3a30 422b24 5c5544 584334 5a4335 6d6656 372c28 332a27 3b322f 4a3c32 3a2a26 322421',
  '221713 221712 221711 241811 241810 231711 231814 221917 231b19 251d1c 27201d 28201e 28201e 28201f 29211f 28211f',
]);

void main() {
  test(
    'The Bear takes its night sky in the top corners, not the brown frame',
    () {
      final tint = PlexBackdropTint.fromSample(theBear)!;
      // Blue clearly over red: the reported bug was a reddish brown here.
      expect(tint.topLeft.b, greaterThan(tint.topLeft.r + 0.03));
      expect(tint.topRight.b, greaterThan(tint.topRight.r + 0.03));
    },
  );

  test('the corners differ, as on a Plex page', () {
    final tint = PlexBackdropTint.fromSample(theBear)!;
    expect(tint.topLeft, isNot(tint.bottomLeft));
  });

  test('the page stays dark enough to read on', () {
    final tint = PlexBackdropTint.fromSample(theBear)!;
    for (final c in [
      tint.topLeft,
      tint.topRight,
      tint.bottomLeft,
      tint.bottomRight,
    ]) {
      expect(c.computeLuminance(), inInclusiveRange(0.012, 0.06));
    }
  });

  test('all-black art has no colour to take', () {
    final black = sample(List.filled(9, List.filled(16, '000000').join(' ')));
    expect(PlexBackdropTint.fromSample(black), isNull);
  });

  test('a large dark-blue setting outweighs a small, strong red subject', () {
    final rows = List.generate(
      9,
      (y) => List.generate(16, (x) {
        // A red figure of 2x3 pixels in a navy scene.
        if (x >= 7 && x <= 8 && y >= 2 && y <= 4) return 'c01818';
        return '1c2a4a';
      }).join(' '),
    );
    final tint = PlexBackdropTint.fromSample(sample(rows))!;
    for (final c in [
      tint.topLeft,
      tint.topRight,
      tint.bottomLeft,
      tint.bottomRight,
    ]) {
      expect(c.b, greaterThan(c.r));
    }
  });
}
