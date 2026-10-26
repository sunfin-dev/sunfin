import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:server_core/server_core.dart' show serverImageHeaders;

import 'plex_style.dart';

/// The page colours Plex derives from the backdrop, one per corner of the
/// page, taken from the same corner of the art and blended across the page
/// (Plex's "UltraBlur"; user, 2026-10-26: "multiple gradients ... more
/// liveliness"). The page's left edge, where the rail sits, runs from
/// [topLeft] to [bottomLeft].
@immutable
class PlexTint {
  final Color topLeft;
  final Color topRight;
  final Color bottomLeft;
  final Color bottomRight;

  const PlexTint({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  const PlexTint.solid(Color color)
    : topLeft = color,
      topRight = color,
      bottomLeft = color,
      bottomRight = color;

  static const fallback = PlexTint.solid(PlexStyle.background);

  /// The colour at a point of the page, x and y from 0 to 1: the corners
  /// blended on an eased curve, which reads as one soft wash rather than
  /// straight ramps.
  Color at(double x, double y) {
    final ex = _ease(x), ey = _ease(y);
    final top = Color.lerp(topLeft, topRight, ex)!;
    final bottom = Color.lerp(bottomLeft, bottomRight, ex)!;
    return Color.lerp(top, bottom, ey)!;
  }

  static double _ease(double t) {
    final c = t.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  @override
  bool operator ==(Object other) =>
      other is PlexTint &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);
}

class PlexTintTween extends Tween<PlexTint> {
  PlexTintTween({super.begin, super.end});

  @override
  PlexTint lerp(double t) => PlexTint(
    topLeft: Color.lerp(begin!.topLeft, end!.topLeft, t)!,
    topRight: Color.lerp(begin!.topRight, end!.topRight, t)!,
    bottomLeft: Color.lerp(begin!.bottomLeft, end!.bottomLeft, t)!,
    bottomRight: Color.lerp(begin!.bottomRight, end!.bottomRight, t)!,
  );
}

/// Paints [tint] over its whole box: a fine mesh whose vertices carry the
/// blended colour, so the GPU fills it in one cheap draw and it can be
/// repainted on every frame of a tint change.
class PlexTintPainter extends CustomPainter {
  final PlexTint tint;

  const PlexTintPainter(this.tint);

  static const _columns = 12;
  static const _rows = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];
    for (var row = 0; row <= _rows; row++) {
      for (var col = 0; col <= _columns; col++) {
        final x = col / _columns, y = row / _rows;
        positions.add(Offset(x * size.width, y * size.height));
        colors.add(tint.at(x, y));
      }
    }
    const stride = _columns + 1;
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _columns; col++) {
        final i = row * stride + col;
        indices.addAll([i, i + 1, i + stride, i + 1, i + stride + 1, i + stride]);
      }
    }
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
      BlendMode.dst,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(PlexTintPainter oldDelegate) => oldDelegate.tint != tint;
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

  /// Where the sample is split into its four quarters.
  static const _midColumn = _sampleWidth ~/ 2;
  static const _midRow = 4;

  /// Hue families the dominant colour is chosen among (30 degrees each).
  static const _hueBins = 12;

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
    final tint = fromSample(ByteData.sublistView(pixels));
    if (tint == null) return null;
    _cache[url] = tint;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return tint;
  }

  /// The tint for a 16x9 RGBA sample of the art, or null when it is too dark
  /// to have a colour.
  @visibleForTesting
  static PlexTint? fromSample(ByteData bytes) {
    // Each corner of the page from the same corner of the art: its quarter,
    // overlapping the middle a little so no corner rests on a sliver.
    final raw = [
      _dominant(bytes, (x, y) => x < _midColumn + 1 && y < _midRow + 1),
      _dominant(bytes, (x, y) => x >= _midColumn - 1 && y < _midRow + 1),
      _dominant(bytes, (x, y) => x < _midColumn + 1 && y >= _midRow - 1),
      _dominant(bytes, (x, y) => x >= _midColumn - 1 && y >= _midRow - 1),
    ];
    // Plex's corners differ in brightness as well as colour (the reference
    // pages run from about 0.01 to 0.06), which is much of what makes them
    // look lit rather than flat. Each corner keeps some of its brightness
    // relative to the others, within a range that stays readable.
    final lums = [for (final c in raw) c.computeLuminance()];
    final mean = lums.reduce((a, b) => a + b) / lums.length;
    final corners = [
      for (var i = 0; i < raw.length; i++)
        _darken(
          raw[i],
          target: mean <= 0
              ? targetLuminance
              : (targetLuminance * math.sqrt(lums[i] / mean)).clamp(
                  targetLuminance * 0.55,
                  targetLuminance * 1.3,
                ),
        ),
    ];
    final any = corners.whereType<Color>().firstOrNull;
    if (any == null) return null;
    // A corner too dark to have a colour borrows its neighbour's.
    Color pick(int i, int across, int down) =>
        corners[i] ?? corners[across] ?? corners[down] ?? any;
    return PlexTint(
      topLeft: pick(0, 1, 2),
      topRight: pick(1, 0, 3),
      bottomLeft: pick(2, 3, 0),
      bottomRight: pick(3, 2, 1),
    );
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

  /// The colour of the art's setting among the sample pixels [include]
  /// accepts: the hue family that covers the most of it, averaged.
  ///
  /// Chosen over a saturation-weighted mean (user, 2026-10-26, after a
  /// side-by-side on 40 titles): that let small, strong patches of the
  /// subject (a red shirt, skin, fire) and dark frames around the art win
  /// over a large background, so The Bear's night sky came out brown.
  /// Near-black and grey pixels carry no reliable hue and count for nothing;
  /// skin tones, almost always the subject, count a little.
  static Color _dominant(ByteData bytes, bool Function(int x, int y) include) {
    final picked = <_Sample>[];
    for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
      final pixel = i ~/ 4;
      if (!include(pixel % _sampleWidth, pixel ~/ _sampleWidth)) continue;
      picked.add(
        _Sample(
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
          bytes.getUint8(i + 3) / 255,
        ),
      );
    }
    final weights = List<double>.filled(_hueBins, 0);
    for (final s in picked) {
      if (s.weight > 0) weights[s.bin] += s.weight;
    }
    var best = 0;
    for (var i = 1; i < _hueBins; i++) {
      if (weights[i] > weights[best]) best = i;
    }
    // Nothing colourful at all: a plain average, which the darkening below
    // turns into the page colour or, for near-black art, the fallback.
    final colourless = weights[best] == 0;
    var r = 0.0, g = 0.0, b = 0.0, weight = 0.0;
    for (final s in picked) {
      final double w;
      if (colourless) {
        w = s.alpha;
      } else {
        // The winning family and its two neighbours, so a hue that sits on a
        // bin edge still counts in full.
        final d = (s.bin - best).abs();
        if (s.weight == 0 || (d > 1 && d != _hueBins - 1)) continue;
        w = s.weight;
      }
      r += s.r * w;
      g += s.g * w;
      b += s.b * w;
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

  /// Scales the colour (keeping its hue) until its luminance is [target].
  /// Near-black art has no hue to keep, so it falls back.
  static Color? _darken(Color color, {double target = targetLuminance}) {
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
      if (scaled(mid).computeLuminance() < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return scaled(lo);
  }
}

/// One sample pixel with what [PlexBackdropTint._dominant] needs of it.
class _Sample {
  final int r, g, b;
  final double alpha;
  late final double _max = math.max(r, math.max(g, b)) / 255;
  late final double _min = math.min(r, math.min(g, b)) / 255;

  _Sample(this.r, this.g, this.b, this.alpha);

  double get value => _max;
  double get saturation => _max == 0 ? 0 : (_max - _min) / _max;

  /// 0-360.
  late final double hue = () {
    final d = _max - _min;
    if (d == 0) return 0.0;
    final rf = r / 255, gf = g / 255, bf = b / 255;
    final double h;
    if (_max == rf) {
      h = ((gf - bf) / d) % 6;
    } else if (_max == gf) {
      h = (bf - rf) / d + 2;
    } else {
      h = (rf - gf) / d + 4;
    }
    return (h * 60 + 360) % 360;
  }();

  int get bin =>
      (hue / 360 * PlexBackdropTint._hueBins).floor() %
      PlexBackdropTint._hueBins;

  static double _ramp(double x, double from, double to) =>
      ((x - from) / (to - from)).clamp(0.0, 1.0);

  /// Warm and moderately saturated: skin and hair, the subject of most art.
  bool get _skinLike =>
      hue <= 50 && saturation >= 0.15 && saturation <= 0.65 && value > 0.25;

  /// How much this pixel speaks for the art's colour: nothing for near-black
  /// (frames, letterboxing, shadows) or grey, a little for skin tones, more
  /// the more saturated it is.
  late final double weight =
      _ramp(value, 0.12, 0.35) *
      _ramp(saturation, 0.08, 0.3) *
      (_skinLike ? 0.15 : 1) *
      (0.3 + saturation) *
      alpha;
}
