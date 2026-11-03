import 'dart:ui' as ui;

import '../sunfin/sunfin_style.dart';
import 'offline_aware_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// A logo display widget with a drop shadow that follows the image shape.
class LogoView extends StatelessWidget {
  final String? imageUrl;
  final ImageProvider? imageProvider;
  final double maxHeight;
  final double maxWidth;

  const LogoView({
    super.key,
    this.imageUrl,
    this.imageProvider,
    this.maxHeight = 80,
    this.maxWidth = 200,
  });

  ImageProvider? get _effectiveProvider {
    if (imageProvider != null) return imageProvider;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return offlineAwareImageProvider(imageUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _effectiveProvider;
    if (provider == null) return const SizedBox.shrink();

    final image = Image(
      image: provider,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    // Sunfin: no blurred shadow copy on the TV. Skia redraws the blur every
    // frame the logo moves, so each scroll of a details page paid for it
    // (2026-10-26); the logo alone reads fine on the tinted page.
    if (SunfinStyle.enabled) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: maxWidth),
        child: RepaintBoundary(child: image),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
        maxWidth: maxWidth,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 3,
              sigmaY: 3,
              tileMode: TileMode.decal,
            ),
            child: Image(
              image: provider,
              fit: BoxFit.contain,
              color: AppColorScheme.scrim.withValues(alpha: 0.6),
              colorBlendMode: BlendMode.srcATop,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          image,
        ],
      ),
    );
  }
}
