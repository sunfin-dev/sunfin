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
///
/// The art sits sharp in the top-right corner and fades into the page colour
/// to the left and bottom. The page colour itself follows the art's tint.
class PlexBackdrop extends StatefulWidget {
  final String? url;

  const PlexBackdrop({super.key, required this.url});

  @override
  State<PlexBackdrop> createState() => _PlexBackdropState();
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
      if (mounted && _isOwner) PlexStyle.pageTint.value = _tint.left;
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
          return DecoratedBox(
            // Plex tints the page with two of the art's colours: its left part
            // behind the header, its lower part under the rows on the right.
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.left, tint.left, tint.bottom],
                stops: const [0, 0.35, 1],
              ),
            ),
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

  /// Fades [child] out towards its left edge (opaque from 16% across) and
  /// its bottom edge (opaque from 20% up) on an eased curve: short, so the
  /// art keeps its strength, and soft, so its edge never shows (user's pick,
  /// "B" of five, 2026-10-26; the fade used to reach 42% and 50% in).
  ///
  /// One mask layer: the two fades are multiplied once into a small alpha
  /// image and stretched over the art. Two stacked gradient masks gave the
  /// same picture for two offscreen layers on every frame of a crossfade.
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

  /// Both fades drawn once into a small image; bilinear sampling keeps the
  /// stretched ramps smooth.
  static ui.Image _buildMaskImage() {
    const width = 192;
    const height = 120;
    const rect = Rect.fromLTWH(0, 0, width + 0.0, height + 0.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = _easedRamp(
          Alignment.centerLeft,
          Alignment.centerRight,
          _leftFade,
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = _easedRamp(
          Alignment.bottomCenter,
          Alignment.topCenter,
          _bottomFade,
        ).createShader(rect),
    );
    canvas.restore();
    return recorder.endRecording().toImageSync(width, height);
  }

  /// How far in from each edge the art reaches full strength (fraction of
  /// the art box).
  static const _leftFade = 0.16;
  static const _bottomFade = 0.20;

  /// Transparent at [begin] to opaque at [length] of the way to [end], on a
  /// smoothstep curve so both ends of the fade are gentle.
  static LinearGradient _easedRamp(
    Alignment begin,
    Alignment end,
    double length,
  ) {
    const steps = 8;
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [
        for (var i = 0; i <= steps; i++)
          Color.fromRGBO(0, 0, 0, _smoothstep(i / steps)),
      ],
      stops: [for (var i = 0; i <= steps; i++) length * i / steps],
    );
  }

  static double _smoothstep(double t) => t * t * (3 - 2 * t);
}
