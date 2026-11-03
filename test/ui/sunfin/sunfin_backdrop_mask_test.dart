import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/sunfin/sunfin_backdrop.dart';

// The values were solved per pixel from Sunfin TV screenshots of three titles
// (2026-11-03); these pin what was measured, not a style choice.
void main() {
  double at(double u, double v) => SunfinBackdrop.artMaskAt(u, v);

  test('the art shows at about 59% where it is clearest', () {
    expect(at(0.6, 0.4), closeTo(0.59, 0.005));
  });

  test('clear at the left and bottom edges', () {
    expect(at(0.0, 0.4), 0);
    expect(at(0.07, 0.4), 0);
    expect(at(0.6, 1.0), lessThan(0.01));
  });

  test('half strength about a fifth of the way in from the left', () {
    expect(at(0.18, 0.4) / 0.59, closeTo(0.5, 0.05));
  });

  test('the bottom fade starts about two thirds down', () {
    expect(at(0.6, 0.62), closeTo(0.59, 0.005));
    expect(at(0.6, 0.83) / 0.59, closeTo(0.5, 0.06));
  });

  test('the bottom-left corner is rounded, not one fade times the other', () {
    // Where both fades are part way, the corner fades further than one fade
    // times the other: separate fades leave a square, brighter corner.
    final both = at(0.25, 0.70) / 0.59;
    final left = at(0.25, 0.4) / 0.59;
    final bottom = at(0.6, 0.70) / 0.59;
    expect(both, lessThan(left * bottom));
  });

  test('top and right edges keep part of the art', () {
    expect(at(0.6, 0.0) / 0.59, closeTo(0.36, 0.04));
    expect(at(1.0, 0.4) / 0.59, closeTo(0.45, 0.04));
  });
}
