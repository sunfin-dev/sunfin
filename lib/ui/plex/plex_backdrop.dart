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
  static const _crossfade = Duration(milliseconds: 400);

  /// The url the parent wants now; a load that finishes for any other url is
  /// stale and dropped.
  String? _wanted;

  /// What is painted: only ever set once its decode is ready, so the old art
  /// stays up until the new one can replace it.
  String? _shownUrl;
  ImageProvider? _shownProvider;

  Color _pageColor = PlexStyle.background;

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
    super.dispose();
  }

  void _request(String? url) {
    _wanted = url;
    _stopLoading();
    if (url == null) {
      if (_shownUrl != null) {
        setState(() {
          _shownUrl = null;
          _shownProvider = null;
          _pageColor = PlexStyle.background;
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
        setState(() {
          _shownUrl = url;
          _shownProvider = provider;
          _pageColor = PlexBackdropTint.cached(url) ?? _pageColor;
        });
        _resolveTint(url, local ? null : headers);
      },
      onError: (_, _) {
        _stopLoading();
        // Broken art: show the plain page rather than the previous item's.
        if (!mounted || _wanted != url) return;
        setState(() {
          _shownUrl = null;
          _shownProvider = null;
          _pageColor = PlexStyle.background;
        });
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  /// Runs after the backdrop has loaded, so the sample decode reads the file
  /// the backdrop just put in the disk cache instead of fetching it again.
  void _resolveTint(String url, Map<String, String>? headers) {
    if (PlexBackdropTint.cached(url) != null) return;
    PlexBackdropTint.resolve(url, headers: headers).then((tint) {
      if (!mounted || _shownUrl != url) return;
      setState(() => _pageColor = tint ?? PlexStyle.background);
    }, onError: (Object _) {});
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

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _pageColor),
      duration: _crossfade,
      curve: Curves.easeOut,
      // The art subtree is built once per url; only the colour layers below
      // rebuild on each tint frame.
      child: RepaintBoundary(
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
      builder: (context, color, artChild) {
        final page = color ?? PlexStyle.background;
        final clear = page.withValues(alpha: 0);
        return ColoredBox(
          color: page,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                right: 0,
                width: PlexStyle.backdropWidth,
                height: PlexStyle.backdropHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    artChild!,
                    // Fading into the page colour with overlays gives the same
                    // result as a dstIn mask without the two saveLayers.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [page, page.withValues(alpha: 0.6), clear],
                          stops: const [0, 0.2, 0.45],
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [page, page.withValues(alpha: 0.6), clear],
                          stops: const [0, 0.15, 0.35],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
