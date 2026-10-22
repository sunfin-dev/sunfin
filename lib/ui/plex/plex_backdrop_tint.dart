import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'plex_style.dart';

/// The two page colours Plex derives from the backdrop: one from the art's
/// left part (behind the header) and one from its lower part (under the rows).
@immutable
class PlexTint {
  final Color left;
  final Color bottom;

  const PlexTint(this.left, this.bottom);

  static const fallback = PlexTint(PlexStyle.background, PlexStyle.background);
}

class PlexTintTween extends Tween<PlexTint> {
  PlexTintTween({super.begin, super.end});

  @override
  PlexTint lerp(double t) => PlexTint(
    Color.lerp(begin!.left, end!.left, t)!,
    Color.lerp(begin!.bottom, end!.bottom, t)!,
  );
}

/// The page tint Plex derives from the backdrop: region averages of the art,
/// darkened until they read as a background.
///
/// Samples the art the backdrop has just decoded for display, scaled down
/// to 16x9 on the GPU: one tiny draw and a 576-byte readback, with no second
/// fetch that could queue behind the posters.
abstract final class PlexBackdropTint {
  /// Relative luminance the tint is darkened to (Plex's page measures
  /// around 0.04-0.06 in the reference screenshots).
  static const targetLuminance = 0.05;

  static const _sampleWidth = 16;
  static const _sampleHeight = 9;
  static const _cacheSize = 30;

  /// Left third of the sample (columns) and bottom third (rows).
  static const _leftColumns = 6;
  static const _bottomFirstRow = 6;

  /// Most recently used last; a hit moves the entry to the end.
  static final LinkedHashMap<String, PlexTint> _cache =
      LinkedHashMap<String, PlexTint>();
  static final Map<String, Future<PlexTint?>> _inFlight = {};

  /// A tint computed earlier for [url], without starting any work.
  static PlexTint? cached(String url) {
    final tint = _cache.remove(url);
    if (tint != null) _cache[url] = tint;
    return tint;
  }

  /// The tint for [url] from its decoded [art], or null when the art can't
  /// be read (the caller keeps [PlexTint.fallback]). Disposes [art].
  static Future<PlexTint?> fromImage(String url, ui.Image art) {
    final hit = cached(url);
    if (hit != null) {
      art.dispose();
      return Future.value(hit);
    }
    final pending = _inFlight[url];
    if (pending != null) {
      art.dispose();
      return pending;
    }
    return _inFlight[url] = _compute(url, art).whenComplete(
      () => _inFlight.remove(url),
    );
  }

  static Future<PlexTint?> _compute(String url, ui.Image art) async {
    ui.Image? image;
    try {
      image = await _downscale(art);
    } finally {
      art.dispose();
    }
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final left = _darken(_average(bytes, (x, y) => x < _leftColumns));
      final bottom = _darken(_average(bytes, (x, y) => y >= _bottomFirstRow));
      if (left == null && bottom == null) return null;
      final tint = PlexTint(
        left ?? bottom ?? PlexStyle.background,
        bottom ?? left ?? PlexStyle.background,
      );
      _cache[url] = tint;
      while (_cache.length > _cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      return tint;
    } finally {
      image.dispose();
    }
  }

  /// Squashes [art] to 16x9, which is all a region average needs.
  static Future<ui.Image> _downscale(ui.Image art) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      art,
      Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
      Rect.fromLTWH(0, 0, _sampleWidth.toDouble(), _sampleHeight.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    return picture
        .toImage(_sampleWidth, _sampleHeight)
        .whenComplete(picture.dispose);
  }

  /// Average of the sample pixels [include] accepts, weighted by alpha and
  /// strongly by saturation: a plain average of varied art comes out grey,
  /// while Plex's page takes on the art's strong colours.
  static Color _average(ByteData bytes, bool Function(int x, int y) include) {
    var r = 0.0, g = 0.0, b = 0.0, weight = 0.0;
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      final pixel = i ~/ 4;
      if (!include(pixel % _sampleWidth, pixel ~/ _sampleWidth)) continue;
      final pr = bytes.getUint8(i);
      final pg = bytes.getUint8(i + 1);
      final pb = bytes.getUint8(i + 2);
      final max = [pr, pg, pb].reduce((a, b) => a > b ? a : b);
      final min = [pr, pg, pb].reduce((a, b) => a < b ? a : b);
      final saturation = max == 0 ? 0.0 : (max - min) / max;
      final w =
          bytes.getUint8(i + 3) / 255 * (saturation * saturation + 0.02);
      r += pr * w;
      g += pg * w;
      b += pb * w;
      weight += w;
    }
    if (weight == 0) return PlexStyle.background;
    return Color.fromARGB(
      255,
      (r / weight).round(),
      (g / weight).round(),
      (b / weight).round(),
    );
  }

  /// Scales the colour (keeping its hue) until its luminance is
  /// [targetLuminance]. Near-black art has no hue to keep, so it falls back.
  static Color? _darken(Color color) {
    final peak = [color.r, color.g, color.b].reduce((a, b) => a > b ? a : b);
    if (peak < 0.02) return null;
    Color scaled(double k) => Color.from(
      alpha: 1,
      red: (color.r * k).clamp(0.0, 1.0),
      green: (color.g * k).clamp(0.0, 1.0),
      blue: (color.b * k).clamp(0.0, 1.0),
    );
    // Luminance rises monotonically with k, so a short bisection finds it.
    var lo = 0.0, hi = 1 / peak;
    for (var i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      if (scaled(mid).computeLuminance() < targetLuminance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return scaled(lo);
  }
}
