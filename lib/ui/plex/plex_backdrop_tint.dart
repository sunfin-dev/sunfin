import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../widgets/image_source.dart';
import 'plex_style.dart';

/// The page colour Plex derives from the backdrop: the art's average colour
/// darkened until it reads as a background.
///
/// Works from a 16x9 decode of the same URL, which comes out of the disk
/// cache the backdrop itself fills, so it costs one tiny decode and a
/// 576-byte readback, all off the build path.
abstract final class PlexBackdropTint {
  /// Relative luminance the tint is darkened to (Plex sits around 0.07).
  static const targetLuminance = 0.07;

  static const _sampleWidth = 16;
  static const _sampleHeight = 9;
  static const _cacheSize = 30;

  /// Most recently used last; a hit moves the entry to the end.
  static final LinkedHashMap<String, Color> _cache =
      LinkedHashMap<String, Color>();
  static final Map<String, Future<Color?>> _inFlight = {};

  /// A tint computed earlier for [url], without starting any work.
  static Color? cached(String url) {
    final color = _cache.remove(url);
    if (color != null) _cache[url] = color;
    return color;
  }

  /// The tint for [url], or null when the art can't be read (the caller
  /// keeps [PlexStyle.background]).
  static Future<Color?> resolve(
    String url, {
    Map<String, String>? headers,
  }) {
    final hit = cached(url);
    if (hit != null) return Future.value(hit);
    return _inFlight[url] ??= _compute(url, headers).whenComplete(
      () => _inFlight.remove(url),
    );
  }

  static Future<Color?> _compute(
    String url,
    Map<String, String>? headers,
  ) async {
    final image = await _decodeSample(url, headers);
    if (image == null) return null;
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final tint = _darken(_average(bytes));
      if (tint == null) return null;
      _cache[url] = tint;
      while (_cache.length > _cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      return tint;
    } finally {
      image.dispose();
    }
  }

  static Future<ui.Image?> _decodeSample(
    String url,
    Map<String, String>? headers,
  ) {
    // Both bounds given: ResizeImage squashes to exactly 16x9, which is all
    // an average needs.
    final provider = ArtworkDecode.provider(
      url,
      width: _sampleWidth,
      height: _sampleHeight,
      headers: headers,
    );
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (completer.isCompleted) {
          info.dispose();
          return;
        }
        // Keep our own handle; the listener's copy is ours to dispose.
        final image = info.image.clone();
        info.dispose();
        completer.complete(image);
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static Color _average(ByteData bytes) {
    var r = 0, g = 0, b = 0, weight = 0;
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      final a = bytes.getUint8(i + 3);
      r += bytes.getUint8(i) * a;
      g += bytes.getUint8(i + 1) * a;
      b += bytes.getUint8(i + 2) * a;
      weight += a;
    }
    if (weight == 0) return PlexStyle.background;
    return Color.fromARGB(255, r ~/ weight, g ~/ weight, b ~/ weight);
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
