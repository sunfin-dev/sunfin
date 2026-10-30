import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:server_core/server_core.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/repositories/item_mutation_repository.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../data/viewmodels/item_detail_view_model.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/detail_section_layout.dart';
import '../../preference/user_preferences.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/focus/key_event_utils.dart';
import '../../util/image_fetch_priority.dart';
import '../navigation/destinations.dart';
import '../screens/detail/item_detail_screen.dart';
import '../screens/detail/nouveau/discovery/nouveau_discovery_section.dart';
import '../screens/detail/nouveau/extras/nouveau_extras_section.dart';
import '../screens/detail/nouveau/people/nouveau_people_section.dart';
import '../widgets/focus/context_menu_sheet.dart';
import '../widgets/image_source.dart';
import '../widgets/navigation_layout.dart';
import 'plex_backdrop.dart';
import 'plex_clock.dart';
import 'plex_detail_parts.dart';
import 'plex_home_header.dart';
import 'plex_rating_line.dart';
import 'plex_style.dart';

/// Plex's show page, where Plex goes when a show is picked in its library
/// (user, 2026-10-23; references 12 and 13):
///
/// - the show's header, as on home;
/// - Play (the episode it's up to) / Watched / More;
/// - its seasons as a row of posters with the unwatched count, OK opening
///   that season's page;
/// - the page's other sections below, in the user's order.
///
/// Anywhere else (Continue Watching, home rows, search) a show still opens
/// the season page at the episode it's up to; only the library asks for this.
class PlexShowPage extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final ValueListenable<String?> backdropUrl;
  final String? selectedMediaSourceId;
  final ValueChanged<String?> onSelectedMediaSourceChanged;

  /// The node the rail hands focus back to; it passes it on to wherever the
  /// user last was on this page.
  final FocusNode? initialFocusNode;

  const PlexShowPage({
    super.key,
    required this.viewModel,
    required this.prefs,
    required this.backdropUrl,
    required this.selectedMediaSourceId,
    required this.onSelectedMediaSourceChanged,
    this.initialFocusNode,
  });

  static bool handles(AggregatedItem? item) => item?.type == 'Series';

  @override
  State<PlexShowPage> createState() => _PlexShowPageState();
}

enum _Region { buttons, seasons, sections }

// Layout, in Plex's 960-wide units (references 12 and 13, the show page).
final _buttonsTop = PlexStyle.s(243);
final _buttonSize = PlexStyle.s(32);
final _buttonGap = PlexStyle.s(12);
final _seasonsLabelTop = PlexStyle.s(300);
final _postersTop = PlexStyle.s(341);
final _posterWidth = PlexStyle.s(120);
final _posterHeight = PlexStyle.s(180);
final _posterGap = PlexStyle.s(16);
const _focusScale = 1.09;

/// How far a focused poster grows past its box on each side.
final _grow = _posterHeight * (_focusScale - 1) / 2;
final _captionGap = PlexStyle.s(8);
final _captionHeight = PlexStyle.s(36);
final _rowHeight =
    _grow + _posterHeight + _grow + _captionGap + _captionHeight;
final _foldHeight = _postersTop - _grow + _rowHeight;
final _rightInset = PlexStyle.s(40);

const _episodeFields = 'Overview,RunTimeTicks,UserData,MediaStreams,PremiereDate';
const _move = Duration(milliseconds: 180);

class _PlexShowPageState extends State<PlexShowPage> {
  final _actionsKey = GlobalKey<DetailActionButtonsState>();
  final _scroll = ScrollController();
  final _rowScroll = ScrollController();

  final _peopleKey = GlobalKey<NouveauPeopleSectionState>();
  final _extrasKey = GlobalKey<NouveauExtrasSectionState>();
  final _discoveryKey = GlobalKey<NouveauDiscoverySectionState>();

  late final FocusNode _entryNode =
      widget.initialFocusNode ?? FocusNode(debugLabel: 'plexShowEntry');
  final _seasonNodes = <String, FocusNode>{};
  final _seasonSelectKeys = LongPressSelectKeyHandler();
  final _buttonNodes = List.generate(
    3,
    (i) => FocusNode(debugLabel: 'plexShowButton$i'),
  );

  List<AggregatedItem> _seasons = const [];

  /// The episode Play starts: the one part way through, else next up. Null
  /// for a show with nothing left, where Play starts it over.
  AggregatedItem? _upTo;

  /// The Watched check right after pressing it, until the item reloads.
  bool? _playedOverride;

  _Region _region = _Region.buttons;
  int _lastButton = 0;
  int _lastSeason = 0;

  /// The top and each section are handed back unchanged unless what they
  /// show changed; the page builds again on every view-model update.
  final _memo = PlexMemo();
  int _prefsRevision = 0;

  ItemDetailViewModel get _vm => widget.viewModel;
  AggregatedItem? get _item => _vm.item;
  bool get _played => _playedOverride ?? _item?.isPlayed ?? false;
  double get _inset => PlexStyle.contentInset;

  MediaServerClient get _client {
    final serverId = _item?.serverId ?? '';
    final fallback = GetIt.instance<MediaServerClient>();
    if (serverId.isEmpty) return fallback;
    return GetIt.instance<MediaServerClientFactory>().getClientIfExists(
          serverId,
        ) ??
        fallback;
  }

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
    widget.prefs.addListener(_onPrefsChanged);
    NavigationLayout.focusDetailsPlayButtonNotifier.value = _entryNode;
    unawaited(_load());
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    widget.prefs.removeListener(_onPrefsChanged);
    if (NavigationLayout.focusDetailsPlayButtonNotifier.value == _entryNode) {
      NavigationLayout.focusDetailsPlayButtonNotifier.value = null;
    }
    if (widget.initialFocusNode == null) _entryNode.dispose();
    for (final node in [..._seasonNodes.values, ..._buttonNodes]) {
      node.dispose();
    }
    _seasonSelectKeys.dispose();
    _scroll.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() => _playedOverride = null);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() => _prefsRevision++);
  }

  // --- Data ---------------------------------------------------------------

  /// Seasons and the episode Play starts; again after anything that changes
  /// what's watched (a season page closed, Watched, the menu).
  Future<void> _load() async {
    final seriesId = _item?.id;
    if (seriesId == null) return;
    await Future.wait([_loadSeasons(seriesId), _loadUpTo(seriesId)]);
  }

  Future<void> _loadSeasons(String seriesId) async {
    try {
      final data = await _client.itemsApi.getSeasons(
        seriesId,
        fields: 'ChildCount,UserData',
      );
      if (mounted) setState(() => _seasons = _mapItems(data));
    } catch (e) {
      debugPrint('[PlexShowPage] seasons for $seriesId: $e');
    }
  }

  /// As the season page has it: the episode part way through first, since
  /// next up can point at a special the user never meant to watch.
  Future<void> _loadUpTo(String seriesId) async {
    try {
      final resume = await _client.itemsApi.getResumeItems(
        parentId: seriesId,
        includeItemTypes: const ['Episode'],
        limit: 1,
      );
      var upTo = _mapItems(resume).firstOrNull;
      if (upTo == null) {
        final nextUp = await _client.itemsApi.getNextUp(
          seriesId: seriesId,
          limit: 1,
        );
        upTo = _mapItems(nextUp).firstOrNull;
      }
      if (mounted) setState(() => _upTo = upTo);
    } catch (e) {
      debugPrint('[PlexShowPage] episode up to for $seriesId: $e');
    }
  }

  /// The first episode of the first regular season, for a show watched to
  /// the end.
  Future<AggregatedItem?> _firstEpisode() async {
    final seriesId = _item?.id;
    if (seriesId == null) return null;
    final regular = _seasons.where((s) => (s.indexNumber ?? 0) > 0);
    final season = regular.firstOrNull ?? _seasons.firstOrNull;
    try {
      final data = await _client.itemsApi.getEpisodes(
        seriesId,
        seasonId: season?.id,
        fields: _episodeFields,
      );
      return _mapItems(data).firstOrNull;
    } catch (e) {
      debugPrint('[PlexShowPage] first episode of $seriesId: $e');
      return null;
    }
  }

  List<AggregatedItem> _mapItems(Map<String, dynamic> data) {
    final serverId = _item?.serverId ?? '';
    return [
      for (final raw in (data['Items'] as List?) ?? const [])
        if (raw is Map)
          AggregatedItem(
            id: raw['Id'].toString(),
            serverId: serverId,
            rawData: Map<String, dynamic>.from(raw),
          ),
    ];
  }

  static bool _inProgress(AggregatedItem e) =>
      !e.isPlayed && (e.playbackPositionTicks ?? 0) > 0;

  // --- Focus --------------------------------------------------------------

  FocusNode _seasonNode(String id) => _seasonNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'plexShowSeason $id'),
  );

  void _restoreFocus() {
    if (_region == _Region.seasons && _focusSeason(_lastSeason)) return;
    _buttonNodes[_lastButton].requestFocus();
  }

  bool _focusSeason(int index) {
    if (_seasons.isEmpty) return false;
    final i = index.clamp(0, _seasons.length - 1);
    final node = _seasonNode(_seasons[i].id);
    if (node.context == null) {
      // Not built yet: the row only builds what is near the screen.
      _scrollRowTo(i, animate: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seasonNode(_seasons[i].id).requestFocus();
      });
    } else {
      node.requestFocus();
    }
    return true;
  }

  void _scrollRowTo(int index, {required bool animate}) {
    if (index < 0 || !_rowScroll.hasClients) return;
    final position = _rowScroll.position;
    final extent = _posterWidth + _posterGap;
    final itemLeft = index * extent;
    final viewport = position.viewportDimension;
    var target = position.pixels;
    if (itemLeft < position.pixels) {
      target = itemLeft;
    } else if (itemLeft + extent > position.pixels + viewport - _inset) {
      target = itemLeft + extent - viewport + _inset * 2;
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    if (animate) {
      _rowScroll.animateTo(target, duration: _move, curve: Curves.easeOutCubic);
    } else {
      _rowScroll.jumpTo(target);
    }
  }

  void _revealTop() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0, duration: _move, curve: Curves.easeOutCubic);
    }
  }

  /// Scrolls just far enough to show the posters and their captions whole,
  /// as Plex does when focus reaches the seasons (reference 13).
  void _revealSeasons() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = (_foldHeight - position.viewportDimension + PlexStyle.s(12))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    _scroll.animateTo(target, duration: _move, curve: Curves.easeOutCubic);
  }

  // --- Keys ---------------------------------------------------------------

  KeyEventResult _onButtonKey(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(event)) {
      if (event is KeyDownEvent) _pressButton(index);
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      if (index > 0) {
        _buttonNodes[index - 1].requestFocus();
      } else {
        NavigationLayout.focusNavbar();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index < _buttonNodes.length - 1) _buttonNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      if (!_focusSeason(_lastSeason)) _focusSection(0);
      return KeyEventResult.handled;
    }
    if (key.isUpKey) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  KeyEventResult _onSeasonKey(int index, KeyEvent event) {
    // OK opens the season on release, held it brings the season's menu, as
    // on every other poster (user, 2026-10-30: mark a watched season
    // unwatched to see it again).
    final season = _seasons[index];
    final select = _seasonSelectKeys.handleKeyEvent(
      event,
      onTap: () => unawaited(_openSeason(season)),
      onLongPress: () => _showSeasonMenu(season),
    );
    if (select != KeyEventResult.ignored) return select;
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isLeftKey) {
      if (index > 0) {
        _focusSeason(index - 1);
      } else {
        NavigationLayout.focusNavbar();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index < _seasons.length - 1) _focusSeason(index + 1);
      return KeyEventResult.handled;
    }
    if (key.isUpKey) {
      _buttonNodes[_lastButton].requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      _focusSection(0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showSeasonMenu(AggregatedItem season) {
    unawaited(
      showContextMenu(context, season, onChanged: () => unawaited(_load())),
    );
  }

  // --- Actions ------------------------------------------------------------

  void _pressButton(int index) {
    switch (index) {
      case 0:
        unawaited(_play());
      case 1:
        unawaited(_toggleWatched());
      default:
        final item = _item;
        if (item == null) return;
        unawaited(
          showContextMenu(context, item, onChanged: () => unawaited(_load())),
        );
    }
  }

  Future<void> _play() async {
    final episode = _upTo ?? await _firstEpisode();
    final actions = _actionsKey.currentState;
    if (episode == null || actions == null || !mounted) return;
    await actions
        .playItem(context, episode, resume: _inProgress(episode))
        .catchError((Object e) => debugPrint('[PlexShowPage] play: $e'));
  }

  Future<void> _toggleWatched() async {
    final item = _item;
    if (item == null) return;
    final played = !_played;
    try {
      await GetIt.instance<ItemMutationRepository>().setPlayed(
        item.id,
        isPlayed: played,
      );
      if (mounted) setState(() => _playedOverride = played);
    } catch (e) {
      debugPrint('[PlexShowPage] watched ${item.id}: $e');
    }
    await _load();
  }

  /// The season's own page, the one Continue Watching leads to, on its
  /// next episode. Coming back refreshes the counts it may have changed.
  Future<void> _openSeason(AggregatedItem season) async {
    await context.push(Destinations.item(season.id, serverId: season.serverId));
    if (mounted) unawaited(_load());
  }

  // --- Sections -----------------------------------------------------------

  /// The page's other sections, in the user's order (Details Screen >
  /// Sections). The seasons are this page's own row, so they stay on top.
  List<({GlobalKey key, Widget child})> _sections() {
    final item = _item;
    if (item == null) return const [];
    final visibility = DetailSectionVisibility.of(widget.prefs);
    final actors = visibility.shows(DetailSection.cast)
        ? _vm.actors
        : const <Map<String, dynamic>>[];
    final directors = visibility.shows(DetailSection.crew)
        ? _vm.directors
        : const <Map<String, dynamic>>[];
    final writers = visibility.shows(DetailSection.crew)
        ? _vm.writers
        : const <Map<String, dynamic>>[];

    final rank = <DetailSection, int>{};
    final ordered = orderedPageSections(widget.prefs);
    for (var i = 0; i < ordered.length; i++) {
      rank[ordered[i]] = i;
    }

    final sections = <({GlobalKey key, Widget child, int rank})>[
      if (actors.isNotEmpty || directors.isNotEmpty || writers.isNotEmpty)
        (
          key: _peopleKey,
          rank: [rank[DetailSection.cast]!, rank[DetailSection.crew]!].reduce(
            (a, b) => a < b ? a : b,
          ),
          child: _memo(
            _peopleKey,
            [item.id, actors, directors, writers, _vm.imageApi],
            () => NouveauPeopleSection(
              key: _peopleKey,
              actors: actors,
              directors: directors,
              writers: writers,
              imageApi: _vm.imageApi,
              serverId: item.serverId,
              onNavigateUp: () => _sectionUp(_peopleKey),
              onNavigateDown: () => _sectionDown(_peopleKey),
            ),
          ),
        ),
      if (visibility.shows(DetailSection.extras) && _vm.features.isNotEmpty)
        (
          key: _extrasKey,
          rank: rank[DetailSection.extras]!,
          child: _memo(
            _extrasKey,
            [item.id, _vm.features, _vm.imageApi, _prefsRevision],
            () => NouveauExtrasSection(
              key: _extrasKey,
              items: _vm.features,
              imageApi: _vm.imageApi,
              prefs: widget.prefs,
              onNavigateUp: () => _sectionUp(_extrasKey),
              onNavigateDown: () => _sectionDown(_extrasKey),
            ),
          ),
        ),
      if (NouveauDiscoverySection.shouldInclude(_vm, visibility))
        (
          key: _discoveryKey,
          rank: rank[DetailSection.moreLikeThis]!,
          // It listens to the view model itself.
          child: _memo(
            _discoveryKey,
            [item.id, visibility, _prefsRevision],
            () => NouveauDiscoverySection(
              key: _discoveryKey,
              viewModel: _vm,
              prefs: widget.prefs,
              visibility: visibility,
              onNavigateUp: () => _sectionUp(_discoveryKey),
              onNavigateDown: () => _sectionDown(_discoveryKey),
              onRevealRequested: _revealSection,
            ),
          ),
        ),
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    return [for (final s in sections) (key: s.key, child: s.child)];
  }

  List<GlobalKey> _sectionKeys = const [];

  /// Focuses the first section from [index] down that can take it.
  bool _focusSection(int index) {
    for (var i = index; i < _sectionKeys.length; i++) {
      if (_focusSectionAt(i)) return true;
    }
    return false;
  }

  /// Up out of the first section goes back to the seasons, or the buttons
  /// for a show without any.
  void _backAboveSections() {
    if (_focusSeason(_lastSeason)) return;
    _revealTop();
    _buttonNodes[_lastButton].requestFocus();
  }

  bool _sectionUp(GlobalKey from) {
    final index = _sectionKeys.indexOf(from);
    for (var i = index - 1; i >= 0; i--) {
      if (_focusSectionAt(i)) return true;
    }
    _backAboveSections();
    return true;
  }

  bool _focusSectionAt(int i) {
    final key = _sectionKeys[i];
    final moved = switch (key) {
      _ when key == _peopleKey => _peopleKey.currentState?.focusTop(),
      _ when key == _extrasKey => _extrasKey.currentState?.focusTop(),
      _ => _discoveryKey.currentState?.focusTop(),
    };
    if (!(moved ?? false)) return false;
    _region = _Region.sections;
    _revealSection(key);
    return true;
  }

  bool _sectionDown(GlobalKey from) {
    final index = _sectionKeys.indexOf(from);
    _focusSection(index + 1);
    // The last section keeps focus rather than letting it fall elsewhere.
    return true;
  }

  void _revealSection(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = key.currentContext;
      if (!mounted || sectionContext == null) return;
      Scrollable.ensureVisible(
        sectionContext,
        alignment: 0.15,
        duration: _move,
        curve: Curves.easeOutCubic,
      );
    });
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null) return const SizedBox.shrink();
    final sections = _sections();
    _sectionKeys = [for (final s in sections) s.key];

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<String?>(
            valueListenable: widget.backdropUrl,
            builder: (context, url, _) => PlexBackdrop(
              url: url != null && url.isNotEmpty ? url : null,
            ),
          ),
        ),
        Focus(
          focusNode: _entryNode,
          skipTraversal: true,
          onFocusChange: (_) {
            if (_entryNode.hasPrimaryFocus) _restoreFocus();
          },
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: _foldHeight,
                  child: _memo(
                    #fold,
                    [
                      item,
                      _vm.ratings,
                      _seasons,
                      _upTo,
                      _played,
                      _prefsRevision,
                    ],
                    () => _buildFold(item),
                  ),
                ),
                for (final section in sections)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      _inset,
                      PlexStyle.s(24),
                      _rightInset,
                      0,
                    ),
                    child: section.child,
                  ),
                SizedBox(height: PlexStyle.s(48)),
              ],
            ),
          ),
        ),
        PlexClock.corner(),
        // Only there to play: its playback path queues the rest of the show
        // and handles prerolls and the external player, as on every page.
        Offstage(
          child: ExcludeFocus(
            child: SizedBox(
              width: 800,
              child: DetailActionButtons(
                key: _actionsKey,
                viewModel: _vm,
                itemId: item.id,
                selectedMediaSourceId: widget.selectedMediaSourceId,
                onSelectedMediaSourceChanged:
                    widget.onSelectedMediaSourceChanged,
                nouveauStyle: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFold(AggregatedItem item) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: PlexHomeHeader(
            item: item,
            leftInset: _inset,
            showCast: false,
            height: _buttonsTop - PlexStyle.s(8),
            ratingLine: PlexRatingLine.of(
              item: item,
              extraRatings: _vm.ratings,
              prefs: widget.prefs,
            ),
          ),
        ),
        Positioned(
          top: _buttonsTop,
          left: _inset,
          child: _buildButtons(),
        ),
        if (_seasons.isNotEmpty) ...[
          Positioned(
            top: _seasonsLabelTop,
            left: _inset,
            child: Text(
              AppLocalizations.of(context).seasons,
              style: PlexStyle.rowTitleStyle.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ),
          Positioned(
            top: _postersTop - _grow,
            left: 0,
            right: 0,
            height: _rowHeight,
            child: _buildSeasonRow(item),
          ),
        ],
      ],
    );
  }

  Widget _buildButtons() {
    final l10n = AppLocalizations.of(context);
    final upTo = _upTo;
    final playLabel =
        upTo != null && _inProgress(upTo) ? l10n.resume : l10n.play;
    return Row(
      children: [
        for (var i = 0; i < _buttonNodes.length; i++) ...[
          if (i > 0) SizedBox(width: _buttonGap),
          Focus(
            focusNode: _buttonNodes[i],
            onFocusChange: (f) {
              if (!f) return;
              _region = _Region.buttons;
              _lastButton = i;
              _revealTop();
            },
            onKeyEvent: (_, event) => _onButtonKey(i, event),
            child: GestureDetector(
              onTap: () => _pressButton(i),
              child: ListenableBuilder(
                listenable: _buttonNodes[i],
                builder: (context, _) => i == 0
                    ? PlexPlayButton(
                        label: playLabel,
                        focused: _buttonNodes[i].hasFocus,
                        size: _buttonSize,
                      )
                    : PlexRoundButton(
                        icon: i == 1 ? Symbols.check_circle : Symbols.more_horiz,
                        filled: i == 1 && _played,
                        focused: _buttonNodes[i].hasFocus,
                        size: _buttonSize,
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSeasonRow(AggregatedItem series) {
    return ListView.builder(
      controller: _rowScroll,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: EdgeInsets.symmetric(horizontal: _inset),
      itemExtent: _posterWidth + _posterGap,
      itemCount: _seasons.length,
      itemBuilder: (context, index) {
        final season = _seasons[index];
        final node = _seasonNode(season.id);
        return Align(
          alignment: Alignment.topLeft,
          child: Focus(
            focusNode: node,
            onFocusChange: (f) {
              if (!f) return;
              _region = _Region.seasons;
              _lastSeason = index;
              _revealSeasons();
              _scrollRowTo(index, animate: true);
            },
            onKeyEvent: (_, event) => _onSeasonKey(index, event),
            child: GestureDetector(
              onTap: () => unawaited(_openSeason(season)),
              onLongPress: () => _showSeasonMenu(season),
              child: ListenableBuilder(
                listenable: node,
                builder: (context, _) => _SeasonCard(
                  season: season,
                  series: series,
                  imageApi: _vm.imageApi,
                  focused: node.hasFocus,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A season's poster (the show's when the season has none), its unwatched
/// count in the corner, and the show and season names under it.
class _SeasonCard extends StatelessWidget {
  final AggregatedItem season;
  final AggregatedItem series;
  final ImageApi imageApi;
  final bool focused;

  const _SeasonCard({
    required this.season,
    required this.series,
    required this.imageApi,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final decodeWidth = ArtworkDecode.widthFor(
      _posterWidth * _focusScale,
      MediaQuery.devicePixelRatioOf(context),
    );
    final ownTag = season.primaryImageTag;
    final seriesTag = series.primaryImageTag;
    final url = ownTag != null
        ? imageApi.getPrimaryImageUrl(
            season.id,
            maxWidth: decodeWidth,
            tag: ownTag,
          )
        : seriesTag != null
        ? imageApi.getPrimaryImageUrl(
            series.id,
            maxWidth: decodeWidth,
            tag: seriesTag,
          )
        : null;
    final unplayed = season.unplayedItemCount ?? 0;
    final radius = BorderRadius.circular(PlexStyle.posterRadius);
    final captionStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.9),
      fontSize: PlexStyle.s(12.5),
    );

    return SizedBox(
      width: _posterWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: _grow),
          AnimatedScale(
            scale: focused ? _focusScale : 1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              width: _posterWidth,
              height: _posterHeight,
              decoration: BoxDecoration(
                borderRadius: radius,
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(
                  color: focused ? Colors.white : Colors.transparent,
                  width: PlexStyle.focusBorderWidth,
                ),
                boxShadow: focused
                    ? const [BoxShadow(color: Color(0x66000000), blurRadius: 12)]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null)
                      Image(
                        image: ArtworkDecode.provider(
                          url,
                          width: decodeWidth,
                          headers: artworkFetchHeaders(
                            url,
                            ImageFetchPriority.normal,
                          ),
                        ),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    if (unplayed > 0 || season.isPlayed)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _CornerBadge(
                          count: unplayed > 0 ? unplayed : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: _grow + _captionGap),
          Text(
            series.name,
            style: captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            season.name,
            style: captionStyle.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Plex's corner tag on a season: the episodes left to watch, or a check
/// once there are none.
class _CornerBadge extends StatelessWidget {
  final int? count;

  const _CornerBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final size = PlexStyle.s(11);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: PlexStyle.s(5),
        vertical: PlexStyle.s(2),
      ),
      color: Colors.black.withValues(alpha: 0.8),
      child: count == null
          ? Icon(Icons.check, size: size * 1.2, color: Colors.white)
          : Text(
              '$count',
              style: TextStyle(
                color: Colors.white,
                fontSize: size,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }
}
