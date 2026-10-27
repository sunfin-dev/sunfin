import 'package:flutter/material.dart';

import 'plex_style.dart';

/// Plex's loading circle: Android's indeterminate arc (it grows and shrinks
/// while it turns) in Plex gold, thin, no track and no text. Replaces the
/// player's logo animation on TV.
class PlexSpinner extends StatelessWidget {
  const PlexSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final size = PlexStyle.s(36);
    // Repaints every frame, so it gets a layer of its own.
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: PlexStyle.s(3),
          color: PlexStyle.accent,
        ),
      ),
    );
  }
}
