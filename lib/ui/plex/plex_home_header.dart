import 'dart:async';

import 'package:flutter/material.dart';
import 'package:server_core/server_core.dart';

import '../../data/models/aggregated_item.dart';
import '../../util/image_fetch_priority.dart';
import '../widgets/image_source.dart';
import 'plex_header_cast.dart';
import 'plex_style.dart';

/// Plex home header: describes the focused item above the rows.
///
/// CONTRACT (do not change the constructor without the lead):
/// - Painted inside a box of full screen width and height [PlexStyle.rowsTop],
///   positioned at the top-left of the home screen, above the backdrop.
/// - [leftInset] is the x of the first poster's left edge; the text column
///   starts there.
/// - [item] null (nothing focused yet) paints nothing.
///
/// - [imageApiFor] gives the item's server image API; with it, a movie or
///   show (and an episode, through its series) shows its logo in place of the
///   title text when the server has one (user, 2026-10-23).
///
/// Uses only fields already on the item: a fetch per focus change would cost
/// the Shield a request for every D-pad press.
class PlexHomeHeader extends StatelessWidget {
  final AggregatedItem? item;
  final double leftInset;
  final ImageApi Function(AggregatedItem item)? imageApiFor;

  /// The cast line under the summary; off where the page has its own cast row.
  final bool showCast;

  const PlexHomeHeader({
    super.key,
    required this.item,
    required this.leftInset,
    this.imageApiFor,
    this.showCast = true,
  });

  static const _fade = PlexMotion.fade;
  static final _scale = PlexStyle.s(1);

  /// Plex lets the title run past the summary column (a long show name
  /// reaches about half the screen), so the column is this wide and every
  /// line but the title is held to [_textWidth]. 960-wide units.
  static const _titleWidth = 620.0;

  @override
  Widget build(BuildContext context) {
    final current = item;
    // Its own layer: the header's text fade and the backdrop's tint fade run
    // together on every focus change, and neither should repaint the other.
    return RepaintBoundary(
      child: SizedBox(
        height: PlexStyle.rowsTop,
        // The header never pushes the rows down: whatever does not fit above
        // rowsTop is cut, and OverflowBox keeps the Column from reporting an
        // overflow while it is.
        child: ClipRect(
          // minWidth 0: the header is placed with a tight full-screen width,
          // which would otherwise force the text column to span the screen.
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Padding(
              padding: EdgeInsets.only(
                left: leftInset,
                top: PlexStyle.headerTop,
              ),
              // The text sizes below are Plex's 960-wide measurements; one
              // scale lands the whole column on Moonfin's TV canvas.
              child: Transform.scale(
                scale: _scale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _titleWidth,
                  child: AnimatedSwitcher(
                    duration: _fade,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previousChildren, ?currentChild],
                    ),
                    child: current == null
                        ? const SizedBox.shrink()
                        : _HeaderText(
                            key: ValueKey(current.id),
                            item: current,
                            showCast: showCast,
                            logoUrl: imageApiFor == null
                                ? null
                                : _logoUrl(current, imageApiFor!(current)),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The summary column width (960-wide units): Plex wraps the summary at
/// ~46% of the screen, while the title may run wider.
const _textWidth = 400.0;

Widget _narrow(Widget child) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: _textWidth),
  child: child,
);

/// Soft shadow so white text stays legible over bright art.
const _shadows = [Shadow(color: Color(0x66000000), blurRadius: 8)];

TextStyle _style(
  double size,
  double alpha, {
  FontWeight weight = FontWeight.w400,
  double? height,
}) => TextStyle(
  color: Colors.white.withValues(alpha: alpha),
  fontSize: size,
  fontWeight: weight,
  height: height,
  shadows: _shadows,
);

final _titleStyle = _style(26, 1, weight: FontWeight.w700);
final _episodeNameStyle = _style(16, 0.75, weight: FontWeight.w600);
final _metaStyle = _style(12.5, 0.85);
final _overviewStyle = _style(13.5, 0.9, height: 1.3);
final _castStyle = _style(12.5, 0.55);

enum _Kind { movieLike, episode, other }

/// The logo box in 960-wide units. Taller than the title line it replaces;
/// the header has that much room below the cast line before the rows.
const _logoMaxWidth = 280.0;
const _logoMaxHeight = 48.0;

/// The item's own logo, or for an episode or season its series' logo, since
/// the header names the series there.
String? _logoUrl(AggregatedItem item, ImageApi imageApi) {
  final maxWidth = ArtworkDecode.stepUp(
    (PlexStyle.s(_logoMaxWidth) * 2).round(),
  );
  final ownTag = item.logoImageTag;
  if (ownTag != null) {
    return imageApi.getLogoImageUrl(item.id, maxWidth: maxWidth, tag: ownTag);
  }
  if (item.type != 'Episode' && item.type != 'Season') return null;
  final seriesTag = item.seriesLogoImageTag;
  final seriesId = item.rawData['ParentLogoItemId']?.toString() ?? item.seriesId;
  if (seriesTag == null || seriesId == null) return null;
  return imageApi.getLogoImageUrl(seriesId, maxWidth: maxWidth, tag: seriesTag);
}

class _HeaderText extends StatelessWidget {
  final AggregatedItem item;
  final String? logoUrl;
  final bool showCast;

  const _HeaderText({
    super.key,
    required this.item,
    this.logoUrl,
    this.showCast = true,
  });

  _Kind get _kind => switch ((item.type ?? '').toLowerCase()) {
    'movie' || 'series' => _Kind.movieLike,
    'episode' => _Kind.episode,
    _ => _Kind.other,
  };

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final seriesName = item.seriesName?.trim();
    final title = kind == _Kind.episode && (seriesName?.isNotEmpty ?? false)
        ? seriesName!
        : item.name;
    final episodeName = kind == _Kind.episode ? item.name.trim() : '';
    final overview = item.overview?.trim() ?? '';
    final meta = switch (kind) {
      _Kind.movieLike => _movieMeta(),
      _Kind.episode => _episodeMeta(),
      _Kind.other => const <Widget>[],
    };
    final genres = kind == _Kind.movieLike
        ? item.genres.take(3).join(', ')
        : '';
    final cast = kind == _Kind.movieLike && showCast ? _cast() : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderTitle(title: title, logoUrl: logoUrl),
        if (episodeName.isNotEmpty && episodeName != title) ...[
          const SizedBox(height: 2),
          Text(
            episodeName,
            style: _episodeNameStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: meta,
          ),
        ],
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 2),
          _narrow(
            Text(
              genres,
              style: _metaStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 10),
          _narrow(
            Text(
              overview,
              style: _overviewStyle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (kind == _Kind.movieLike && showCast)
          _narrow(_CastLine(item: item, fromItem: cast)),
      ],
    );
  }

  List<Widget> _movieMeta() => [
    if (item.productionYear case final year?) _metaText('$year'),
    if (_formatDuration(item.runtime) case final runtime?) _metaText(runtime),
    if (_rating() case final rating?) _metaText(rating),
    ?_resumePill(),
  ];

  List<Widget> _episodeMeta() {
    final season = item.parentIndexNumber;
    final episode = item.indexNumber;
    final number = [
      if (season != null) 'S$season',
      if (episode != null) 'E$episode',
    ].join(' · ');
    return [
      if (number.isNotEmpty) _metaText(number),
      if (_formatDate(item.premiereDate) case final date?) _metaText(date),
      if (_formatDuration(item.runtime) case final runtime?) _metaText(runtime),
      if (_rating() case final rating?) _metaText(rating),
      ?_resumePill(),
    ];
  }

  Widget _metaText(String text) => Text(text, style: _metaStyle, maxLines: 1);

  String? _rating() {
    final rating = item.officialRating?.trim();
    return rating == null || rating.isEmpty ? null : rating;
  }

  /// Plex's "2h 35m left" chip; only when the item is part way through.
  Widget? _resumePill() {
    final runtime = item.runtime;
    final position = item.playbackPosition;
    if (runtime == null || position == null) return null;
    if (position <= Duration.zero || position >= runtime) return null;
    final left = _formatDuration(runtime - position);
    if (left == null) return null;
    final progress = position.inMilliseconds / runtime.inMilliseconds;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                color: PlexStyle.accent,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$left left',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// First three actors when the row already carried People; otherwise
  /// [_CastLine] fetches them.
  String _cast() => item.people
      .where((p) => (p['Type'] as String?)?.toLowerCase() == 'actor')
      .map((p) => (p['Name'] as String?)?.trim() ?? '')
      .where((name) => name.isNotEmpty)
      .take(3)
      .join(', ');
}

enum _TitleMode { pending, logo, text }

/// The title line: the item's logo art when the server has one, else the
/// title text. A logo not seen yet is only requested once focus settles, like
/// the cast line, and the box keeps the logo's height while it loads so the
/// lines below don't jump when it lands. A logo that fails to load falls back
/// to the text.
class _HeaderTitle extends StatefulWidget {
  final String title;
  final String? logoUrl;

  const _HeaderTitle({required this.title, required this.logoUrl});

  @override
  State<_HeaderTitle> createState() => _HeaderTitleState();
}

class _HeaderTitleState extends State<_HeaderTitle> {
  static const _settle = Duration(milliseconds: 150);
  static const _fadeIn = Duration(milliseconds: 160);

  /// Logo urls already tried this session: true loaded, false failed.
  static final Map<String, bool> _tried = {};

  _TitleMode _mode = _TitleMode.text;
  bool _fade = false;
  bool _started = false;
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The decode size needs MediaQuery, which initState can't read.
    if (_started) return;
    _started = true;
    final url = widget.logoUrl;
    if (url == null || _tried[url] == false) return;
    _mode = _TitleMode.pending;
    if (_tried[url] == true) {
      _load(url);
    } else {
      _timer = Timer(_settle, () => _load(url));
    }
  }

  void _load(String url) {
    if (!mounted) return;
    final provider = ArtworkDecode.provider(
      url,
      width: ArtworkDecode.widthFor(
        PlexStyle.s(_logoMaxWidth),
        MediaQuery.devicePixelRatioOf(context),
      ),
      headers: artworkFetchHeaders(url, ImageFetchPriority.high),
    );
    var synchronous = true;
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        _stop();
        _remember(url, true);
        if (!mounted) return;
        if (synchronous) {
          _provider = provider;
          _mode = _TitleMode.logo;
          return;
        }
        setState(() {
          _provider = provider;
          _mode = _TitleMode.logo;
          _fade = true;
        });
      },
      onError: (_, _) {
        _stop();
        _remember(url, false);
        if (!mounted) return;
        if (synchronous) {
          _mode = _TitleMode.text;
          return;
        }
        setState(() => _mode = _TitleMode.text);
      },
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
    synchronous = false;
  }

  static void _remember(String url, bool loaded) {
    if (_tried.length > 500) _tried.clear();
    _tried[url] = loaded;
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _TitleMode.text:
        return Text(
          widget.title,
          style: _titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case _TitleMode.pending:
        return const SizedBox(height: _logoMaxHeight);
      case _TitleMode.logo:
        final logo = SizedBox(
          width: _logoMaxWidth,
          height: _logoMaxHeight,
          child: Image(
            image: _provider!,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            semanticLabel: widget.title,
            gaplessPlayback: true,
          ),
        );
        if (!_fade) return logo;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: _fadeIn,
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: logo,
        );
    }
  }
}

/// The cast line under the summary. The header is keyed by item, so each
/// focus change builds a fresh line; the delay means scrolling past titles
/// sends no requests, only the one focus rests on.
class _CastLine extends StatefulWidget {
  final AggregatedItem item;
  final String fromItem;

  const _CastLine({required this.item, required this.fromItem});

  @override
  State<_CastLine> createState() => _CastLineState();
}

class _CastLineState extends State<_CastLine> {
  static const _settle = Duration(milliseconds: 350);

  String _cast = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cast = widget.fromItem;
    if (_cast.isNotEmpty) return;
    final cached = PlexHeaderCast.cached(widget.item);
    if (cached != null) {
      _cast = cached.join(', ');
      return;
    }
    _timer = Timer(_settle, () async {
      final names = await PlexHeaderCast.resolve(widget.item);
      if (mounted && names.isNotEmpty) setState(() => _cast = names.join(', '));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cast.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        _cast,
        style: _castStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// "2h 49m", "2h", "23m"; null below one minute.
String? _formatDuration(Duration? d) {
  if (d == null) return null;
  final minutes = d.inMinutes;
  if (minutes <= 0) return null;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "May 13, 2024". The server sends a UTC midnight, so the date is read as
/// sent: converting to local time would show the day before west of UTC.
String? _formatDate(DateTime? date) {
  if (date == null) return null;
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}
