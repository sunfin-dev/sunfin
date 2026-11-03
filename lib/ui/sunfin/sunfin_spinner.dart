import 'package:flutter/material.dart';

import 'sunfin_style.dart';

/// The reference design's loading circle: Android's indeterminate arc (it grows and shrinks
/// while it turns) in Sunfin gold, thin, no track and no text. Replaces the
/// player's logo animation on TV.
class SunfinSpinner extends StatelessWidget {
  const SunfinSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final size = SunfinStyle.s(36);
    // Repaints every frame, so it gets a layer of its own.
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: SunfinStyle.s(3),
          color: SunfinStyle.accent,
        ),
      ),
    );
  }
}
