import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:server_core/server_core.dart' show serverImageHeaders;

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
/// Asks the server for a 32-pixel-wide PNG of the same backdrop (about a
/// kilobyte, fetched directly so it never queues behind the posters) and
/// averages it on the CPU. A GPU route (downscale or readback of the decoded
/// art) never completed on the Shield, which left every page grey.
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

  /// The tint for [url], or null when the art can't be read (the caller
  /// keeps [PlexTint.fallback]).
  static Future<PlexTint?> resolve(String url) {
    final hit = cached(url);
    if (hit != null) return Future.value(hit);
    // A block body on purpose: `=> _inFlight.remove(url)` would hand
    // whenComplete this very future to wait for, and it never completed.
    return _inFlight[url] ??= _compute(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  static Future<PlexTint?> _compute(String url) async {
    final sampleUrl = _sampleUrl(url);
    if (sampleUrl == null) return null;
    final response = await http
        .get(sampleUrl, headers: serverImageHeaders)
        .timeout(_fetchTimeout);
    if (response.statusCode != 200) return null;
    final decoded = img.decodeImage(response.bodyBytes);
    if (decoded == null) return null;
    final pixels = img
        .copyResize(
          decoded,
          width: _sampleWidth,
          height: _sampleHeight,
          interpolation: img.Interpolation.average,
        )
        .getBytes(order: img.ChannelOrder.rgba);
    final bytes = ByteData.sublistView(pixels);
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
  }

  static const _fetchTimeout = Duration(seconds: 5);

  /// The same Jellyfin image at sample size, as PNG. Null for art that isn't
  /// a server image (e.g. a TMDB URL), which keeps the fallback page.
  static Uri? _sampleUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.path.contains('/Images/')) return null;
    final query = Map<String, String>.of(uri.queryParameters)
      ..removeWhere(
        (k, _) => const {
          'maxwidth',
          'maxheight',
          'width',
          'height',
          'fillwidth',
          'fillheight',
          'quality',
          'format',
        }.contains(k.toLowerCase()),
      )
      ..['maxWidth'] = '32'
      ..['format'] = 'png';
    return uri.replace(queryParameters: query);
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
