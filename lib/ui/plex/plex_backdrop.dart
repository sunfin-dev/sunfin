import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../util/image_fetch_priority.dart';
import '../theme/vibrance.dart';
import '../widgets/image_source.dart';
import 'plex_backdrop_tint.dart';
import 'plex_style.dart';

/// Plex home/detail background: page colour plus the sharp backdrop art.
///
/// CONTRACT (do not change the constructor without the lead):
/// - Fills its parent (used as the bottom layer of a full-screen Stack).
/// - [url] is the backdrop URL from BackgroundService (null: colour only).
/// - [showArt] false paints only the page colour taken from [url] (the
///   library page, which Plex shows without art).
///
/// The art sits sharp in the top-right corner and fades into the page colour
/// to the left and bottom. The page colour itself follows the art's tint.
class PlexBackdrop extends StatefulWidget {
  final String? url;
  final bool showArt;

  const PlexBackdrop({super.key, required this.url, this.showArt = true});

  @override
  State<PlexBackdrop> createState() => _PlexBackdropState();

  /// How much of the art shows at ([u], [v]) of the art box, 0-1 from its
  /// top-left corner.
  ///
  /// Measured on the Plex TV app (2026-11-03): the movie page, show page and
  /// home of three titles, each solved per pixel against Plex's own copy of
  /// the art, agree on one box and one mask. The art never shows at full
  /// strength, only [_artOpacity] of it over the page colour. It fades out
  /// to the left and bottom with a rounded corner between the two, and
  /// softly towards the top and right edges.
  @visibleForTesting
  static double artMaskAt(double u, double v) {
    final left = math.max(0.0, (_leftOpaque - u) / (_leftOpaque - _leftClear));
    final bottom = math.max(
      0.0,
      (v - _bottomOpaque) / (_bottomClear - _bottomOpaque),
    );
    final corner = math
        .pow(
          math.pow(left, _cornerNorm) + math.pow(bottom, _cornerNorm),
          1 / _cornerNorm,
        )
        .toDouble();
    return _artOpacity *
        (1 - _ease(corner)) *
        _ease((v - _topClear) / (_topOpaque - _topClear)) *
        (1 - _ease((u - _rightFrom) / (_rightTo - _rightFrom)));
  }

  static const _artOpacity = 0.59;

  /// Fractions of the art box: clear at the first, full at the second.
  static const _leftClear = 0.076;
  static const _leftOpaque = 0.289;
  static const _bottomOpaque = 0.643;
  static const _bottomClear = 1.019;

  /// 1 cuts the bottom-left corner straight across, 2 rounds it as a circle.
  static const _cornerNorm = 1.2;

  /// The top edge keeps about a third, the right edge about a half.
  static const _topClear = -0.146;
  static const _topOpaque = 0.221;
  static const _rightFrom = 0.85;
  static const _rightTo = 1.13;

  static double _ease(double t) {
    final c = t.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }
}

class _PlexBackdropState extends State<PlexBackdrop> {
  static const _crossfade = PlexStyle.tintDuration;

  /// Every mounted backdrop, oldest first. A details page stacks its own on
  /// top of home's, and only the newest one, the page on screen, sets the
  /// rail's colour. Closing it hands the colour back to the one below.
  static final List<_PlexBackdropState> _owners = [];

  bool get _isOwner => _owners.isNotEmpty && identical(_owners.last, this);

  void _publishTint() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOwner) {
        PlexStyle.pageTint.value = (_tint.topLeft, _tint.bottomLeft);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _owners.add(this);
  }

  /// The url the parent wants now; a load that finishes for any other url is
  /// stale and dropped.
  String? _wanted;

  /// What is painted: only ever set once its decode is ready, so the old art
  /// stays up until the new one can replace it.
  String? _shownUrl;
  ImageProvider? _shownProvider;

  PlexTint _tint = PlexTint.fallback;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The decode size needs MediaQuery, which initState can't read.
    if (!_started) {
      _started = true;
      _request(widget.url);
      // With nothing to show yet the page is the plain colour; say so, or
      // the rail keeps the colour of the page below until art arrives.
      if (widget.url == null) _publishTint();
    }
  }

  @override
  void didUpdateWidget(PlexBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) _request(widget.url);
  }

  @override
  void dispose() {
    _stopLoading();
    final wasOwner = _isOwner;
    _owners.remove(this);
    if (wasOwner && _owners.isNotEmpty) _owners.last._publishTint();
    super.dispose();
  }

  /// Sets the page tint and, after this frame, publishes its left colour for
  /// the collapsed rail (publishing mid-build would rebuild another widget
  /// during this one's build). Call inside setState.
  void _applyTint(PlexTint tint) {
    _tint = tint;
    _publishTint();
  }

  void _request(String? url) {
    _wanted = url;
    _stopLoading();
    if (url == null) {
      if (_shownUrl != null) {
        setState(() {
          _shownUrl = null;
          _shownProvider = null;
          _applyTint(PlexTint.fallback);
        });
      }
      return;
    }
    if (url == _shownUrl) return;

    if (!widget.showArt) {
      // Only the colour is wanted: no art to fetch and decode.
      _shownUrl = url;
      final cached = PlexBackdropTint.cached(url);
      if (cached != null) {
        // Both callers build next, so no setState.
        _applyTint(cached);
      } else {
        _resolveTint(url);
      }
      return;
    }

    final local = isLocalImagePath(url);
    final headers = local
        ? null
        : artworkFetchHeaders(url, ImageFetchPriority.high);
    final provider = ArtworkDecode.provider(
      url,
      width: ArtworkDecode.widthFor(
        PlexStyle.backdropWidth,
        MediaQuery.devicePixelRatioOf(context),
        layoutHeight: PlexStyle.backdropHeight,
        sourceAspectRatio: 16 / 9,
      ),
      headers: headers,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        _stopLoading();
        if (!mounted || _wanted != url) return;
        final cached = PlexBackdropTint.cached(url);
        setState(() {
          _shownUrl = url;
          _shownProvider = provider;
          if (cached != null) _applyTint(cached);
        });
        if (cached == null) _resolveTint(url);
      },
      onError: (_, _) {
        _stopLoading();
        // Broken art: show the plain page rather than the previous item's.
        if (!mounted || _wanted != url) return;
        setState(() {
          _shownUrl = null;
          _shownProvider = null;
          _applyTint(PlexTint.fallback);
        });
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _resolveTint(String url) {
    PlexBackdropTint.resolve(url).then(
      (tint) {
        if (!mounted || _shownUrl != url) return;
        setState(() => _applyTint(tint ?? PlexTint.fallback));
      },
      onError: (Object e) {
        // A failed sample only costs the tint; say why in the log.
        debugPrint('[PlexTint] $url: $e');
      },
    );
  }

  void _stopLoading() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final shownUrl = _shownUrl;
    final provider = _shownProvider;
    final art = shownUrl == null || provider == null
        ? const SizedBox.expand(key: ValueKey<String?>(null))
        : SizedBox.expand(
            key: ValueKey<String?>(shownUrl),
            child: Image(
              image: provider,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          );

    // Its own layer: each frame of a tint fade repaints only the page colour
    // and art, not the header and rows laid over it.
    return RepaintBoundary(
      child: TweenAnimationBuilder<PlexTint>(
        tween: PlexTintTween(end: _tint),
        duration: _crossfade,
        curve: Curves.easeOut,
        // The art subtree is built once per url; only the page gradient below
        // rebuilds on each tint frame.
        child: RepaintBoundary(
          // The art fades to transparent (not to one colour) so the two-tone
          // page shows through its edges, as in Plex.
          child: _fadeMask(
            child: Vibrance.wrap(
              AnimatedSwitcher(
                duration: _crossfade,
                switchInCurve: Curves.easeOut,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                // Only the incoming art fades; the outgoing one stays opaque
                // beneath it, so the page colour never shows through mid-fade.
                // Clearing to no art is the exception: then the old art fades out.
                transitionBuilder: (child, animation) {
                  final incoming = child.key == ValueKey<String?>(shownUrl);
                  if (incoming || shownUrl == null) {
                    return FadeTransition(opacity: animation, child: child);
                  }
                  return child;
                },
                child: art,
              ),
            ),
          ),
        ),
        builder: (context, tint, artChild) {
          // Plex's four-corner wash: each corner of the page in the colour of
          // the same corner of the art, blended across the page.
          return CustomPaint(
            painter: PlexTintPainter(tint),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  width: PlexStyle.backdropWidth,
                  height: PlexStyle.backdropHeight,
                  child: artChild!,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Fades [child] as Plex does ([PlexBackdrop.artMaskAt]).
  ///
  /// One mask layer: the mask is drawn once into a small alpha image and
  /// stretched over the art. Stacked gradient masks gave the same picture
  /// for several offscreen layers on every frame of a crossfade.
  static Widget _fadeMask({required Widget child}) {
    final mask = _maskImage;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => ImageShader(
        mask,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.diagonal3Values(
          rect.width / mask.width,
          rect.height / mask.height,
          1,
        ).storage,
        filterQuality: FilterQuality.low,
      ),
      child: child,
    );
  }

  static final ui.Image _maskImage = _buildMaskImage();

  /// The mask drawn once, a pixel at a time, into a small image (16:9 like
  /// the box); bilinear sampling keeps it smooth when stretched.
  static ui.Image _buildMaskImage() {
    const width = 192;
    const height = 108;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final alpha = PlexBackdrop.artMaskAt(
          (x + 0.5) / width,
          (y + 0.5) / height,
        );
        if (alpha <= 0) continue;
        paint.color = Color.fromRGBO(0, 0, 0, alpha);
        canvas.drawRect(Rect.fromLTWH(x + 0.0, y + 0.0, 1, 1), paint);
      }
    }
    return recorder.endRecording().toImageSync(width, height);
  }
}
