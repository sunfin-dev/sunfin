import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:server_core/server_core.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/repositories/item_mutation_repository.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../data/viewmodels/item_detail_view_model.dart';
import '../../preference/detail_section_layout.dart';
import '../../preference/user_preferences.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/image_fetch_priority.dart';
import '../../util/language_codes.dart';
import '../../util/language_matching.dart';
import '../screens/detail/item_detail_screen.dart';
import '../screens/detail/nouveau/discovery/nouveau_discovery_section.dart';
import '../screens/detail/nouveau/extras/nouveau_extras_section.dart';
import '../screens/detail/nouveau/people/nouveau_people_section.dart';
import '../widgets/focus/context_menu_sheet.dart';
import '../widgets/image_source.dart';
import '../widgets/navigation_layout.dart';
import 'plex_backdrop.dart';
import 'plex_clock.dart';
import 'plex_home_header.dart';
import 'plex_style.dart';

/// Plex's season page, which is where Plex sends you for an episode too
/// (user, 2026-10-23; reference 14 and the user's South Park screenshot):
///
/// - season tabs along the top, the season on screen underlined, scrolled
///   so it is always in view;
/// - a header describing the focused episode, as on home;
/// - the season's episodes as one row of wide thumbnails (OK plays one);
/// - Play / Watched / More for the focused episode, with its resolution,
///   audio and subtitle on the right;
/// - the page's other sections below, in the user's order.
///
/// The art sits in the top right over a colour taken from it (PlexBackdrop),
/// which the rail takes too.
class PlexSeasonPage extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final ValueListenable<String?> backdropUrl;
  final String? selectedMediaSourceId;
  final ValueChanged<String?> onSelectedMediaSourceChanged;

  /// The node the rail hands focus back to; it passes it on to wherever the
  /// user last was on this page.
  final FocusNode? initialFocusNode;

  const PlexSeasonPage({
    super.key,
    required this.viewModel,
    required this.prefs,
    required this.backdropUrl,
    required this.selectedMediaSourceId,
    required this.onSelectedMediaSourceChanged,
    this.initialFocusNode,
  });

  /// The item types this page draws. A show opens on it too, at the episode
  /// it's up to, the same page Continue Watching leads to (user, 2026-10-23).
  static bool handles(AggregatedItem? item) =>
      item?.type == 'Episode' ||
      item?.type == 'Season' ||
      item?.type == 'Series';

  @override
  State<PlexSeasonPage> createState() => _PlexSeasonPageState();
}

/// The episode a season opens on.
@visibleForTesting
AggregatedItem? plexNextToWatch(List<AggregatedItem> episodes) =>
    _PlexSeasonPageState._nextToWatch(episodes);

/// A media chip's text, e.g. "English (EAC3 5.1)".
@visibleForTesting
String plexStreamLabel(Map<String, dynamic> stream, {bool audio = false}) =>
    _MediaChips._streamLabel(stream, audio: audio);

enum _Region { tabs, row, buttons, sections }

// Layout, in Plex's 960-wide units (reference 14, the season page).
final _tabsTop = PlexStyle.s(20);
final _tabHeight = PlexStyle.s(26);
final _rowTop = PlexStyle.s(246);
final _cardWidth = PlexStyle.s(170);
final _cardHeight = PlexStyle.s(96);
final _cardGap = PlexStyle.s(20);
const _focusScale = 1.094;
final _buttonsTop = PlexStyle.s(362);
final _buttonSize = PlexStyle.s(32);
final _buttonGap = PlexStyle.s(12);
final _rightInset = PlexStyle.s(40);
final _foldHeight = PlexStyle.s(440);

const _episodeFields = 'Overview,RunTimeTicks,UserData,MediaStreams,PremiereDate';
const _move = Duration(milliseconds: 180);

class _PlexSeasonPageState extends State<PlexSeasonPage> {
  final _actionsKey = GlobalKey<DetailActionButtonsState>();
  final _scroll = ScrollController();
  final _rowScroll = ScrollController();

  final _peopleKey = GlobalKey<NouveauPeopleSectionState>();
  final _extrasKey = GlobalKey<NouveauExtrasSectionState>();
  final _discoveryKey = GlobalKey<NouveauDiscoverySectionState>();

  late final FocusNode _entryNode =
      widget.initialFocusNode ?? FocusNode(debugLabel: 'plexSeasonEntry');
  final _tabNodes = <String, FocusNode>{};
  final _cardNodes = <String, FocusNode>{};
  final _buttonNodes = List.generate(
    3,
    (i) => FocusNode(debugLabel: 'plexSeasonButton$i'),
  );

  List<AggregatedItem> _seasons = const [];
  final _episodesBySeason = <String, List<AggregatedItem>>{};

  /// The season whose episodes are on screen, and so the one underlined.
  /// Only ever set together with its episodes, so the tab can't disagree with
  /// the row (Plex gets this wrong when opening an episode).
  String? _seasonId;
  String? _wantedSeasonId;
  /// The episode the header, chips and Watched check describe. A notifier
  /// rather than page state, so a step along the row redraws only those and
  /// not the tabs, the row and the sections below.
  final _focusedNotifier = ValueNotifier<AggregatedItem?>(null);
  AggregatedItem? get _focused => _focusedNotifier.value;
  _Region _region = _Region.row;
  int _lastButton = 0;
  bool _initialFocusDone = false;
  Timer? _seasonDebounce;

  ItemDetailViewModel get _vm => widget.viewModel;
  AggregatedItem? get _item => _vm.item;
  List<AggregatedItem> get _episodes =>
      _episodesBySeason[_seasonId] ?? const [];
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

  String? get _seriesId =>
      _item?.type == 'Series' ? _item?.id : _item?.seriesId;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
    NavigationLayout.focusDetailsPlayButtonNotifier.value = _entryNode;
    unawaited(_loadSeasons());
  }

  @override
  void dispose() {
    _seasonDebounce?.cancel();
    _vm.removeListener(_onViewModelChanged);
    if (NavigationLayout.focusDetailsPlayButtonNotifier.value == _entryNode) {
      NavigationLayout.focusDetailsPlayButtonNotifier.value = null;
    }
    if (widget.initialFocusNode == null) _entryNode.dispose();
    for (final node in [..._tabNodes.values, ..._cardNodes.values]) {
      node.dispose();
    }
    for (final node in _buttonNodes) {
      node.dispose();
    }
    _scroll.dispose();
    _rowScroll.dispose();
    _focusedNotifier.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  // --- Data ---------------------------------------------------------------

  Future<void> _loadSeasons() async {
    final item = _item;
    final seriesId = _seriesId;
    if (item == null || seriesId == null) return;
    var seasonId = item.type == 'Season' ? item.id : item.seasonId;
    var focusEpisodeId = item.type == 'Episode' ? item.id : null;
    if (item.type == 'Series') {
      final upTo = await _episodeUpTo(seriesId);
      seasonId = upTo?.seasonId;
      focusEpisodeId = upTo?.id;
    }
    try {
      final data = await _client.itemsApi.getSeasons(
        seriesId,
        fields: 'ChildCount,UserData',
      );
      if (!mounted) return;
      final seasons = _mapItems(data);
      // An episode that came without its season id still has its number.
      if (item.type == 'Episode') {
        seasonId ??= seasons
            .where((s) => s.indexNumber == item.parentIndexNumber)
            .firstOrNull
            ?.id;
      }
      // A show with nothing under way: its first regular season with
      // anything left to watch, else its first regular season.
      seasonId ??= _firstSeasonToWatch(seasons)?.id;
      setState(() => _seasons = seasons);
    } catch (e) {
      debugPrint('[PlexSeasonPage] seasons for $seriesId: $e');
    }
    if (seasonId == null) return;
    await _showSeason(seasonId, focusEpisodeId: focusEpisodeId);
  }

  /// The episode a show is up to, as Continue Watching has it: the one part
  /// way through, else the server's next up. The in-progress one goes first
  /// because next up can point at a special the user never meant to watch.
  Future<AggregatedItem?> _episodeUpTo(String seriesId) async {
    try {
      final resume = await _client.itemsApi.getResumeItems(
        parentId: seriesId,
        includeItemTypes: const ['Episode'],
        limit: 1,
      );
      final inProgress = _mapItems(resume).firstOrNull;
      if (inProgress != null) return inProgress;
      final nextUp = await _client.itemsApi.getNextUp(
        seriesId: seriesId,
        limit: 1,
      );
      return _mapItems(nextUp).firstOrNull;
    } catch (e) {
      debugPrint('[PlexSeasonPage] episode up to for $seriesId: $e');
      return null;
    }
  }

  static AggregatedItem? _firstSeasonToWatch(List<AggregatedItem> seasons) {
    final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0).toList();
    final pool = regular.isEmpty ? seasons : regular;
    return pool.where((s) => (s.unplayedItemCount ?? 0) > 0).firstOrNull ??
        pool.firstOrNull;
  }

  /// Loads [seasonId] if needed and puts it on screen, focused episode and
  /// underlined tab together. A later call wins over an earlier slow one.
  Future<void> _showSeason(String seasonId, {String? focusEpisodeId}) async {
    _wantedSeasonId = seasonId;
    var episodes = _episodesBySeason[seasonId];
    if (episodes == null) {
      try {
        final data = await _client.itemsApi.getEpisodes(
          _seriesId!,
          seasonId: seasonId,
          fields: _episodeFields,
        );
        episodes = _mapItems(data);
        _episodesBySeason[seasonId] = episodes;
      } catch (e) {
        debugPrint('[PlexSeasonPage] episodes of $seasonId: $e');
        return;
      }
    }
    if (!mounted || _wantedSeasonId != seasonId) return;
    final target =
        episodes.where((e) => e.id == focusEpisodeId).firstOrNull ??
        _nextToWatch(episodes);
    setState(() {
      _seasonId = seasonId;
      _focusedNotifier.value = target;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || target == null) return;
      // A season opens with its focused episode at the start of the row, not
      // squeezed against the far edge with half cards beside the rail.
      _startRowAt(episodes!.indexOf(target));
      // And its tab in view: Plex leaves a late season's tab off screen when
      // it opens an episode, which is the bug the user asked us not to copy.
      _revealTab(seasonId, animate: _initialFocusDone);
      if (!_initialFocusDone) {
        _initialFocusDone = true;
        _focusEpisode(target);
      }
    });
  }

  /// Fetches the season on screen again, e.g. after marking one watched.
  Future<void> _refreshSeason() async {
    final seasonId = _seasonId;
    if (seasonId == null) return;
    final keep = _focused?.id;
    _episodesBySeason.remove(seasonId);
    await _showSeason(seasonId, focusEpisodeId: keep);
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

  /// Where Plex lands in a season: the one part way through, else the first
  /// one not watched, else the first.
  static AggregatedItem? _nextToWatch(List<AggregatedItem> episodes) {
    if (episodes.isEmpty) return null;
    return episodes.where(_inProgress).firstOrNull ??
        episodes.where((e) => !e.isPlayed).firstOrNull ??
        episodes.first;
  }

  static bool _inProgress(AggregatedItem e) =>
      !e.isPlayed && (e.playbackPositionTicks ?? 0) > 0;

  // --- Focus --------------------------------------------------------------

  FocusNode _tabNode(String id) =>
      _tabNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'plexTab $id'));

  FocusNode _cardNode(String id) =>
      _cardNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'plexEp $id'));

  void _restoreFocus() {
    switch (_region) {
      case _Region.tabs:
        if (_focusSelectedTab()) return;
      case _Region.buttons:
        _buttonNodes[_lastButton].requestFocus();
        return;
      case _Region.row:
      case _Region.sections:
        break;
    }
    final focused = _focused;
    if (focused != null) {
      _focusEpisode(focused);
    } else {
      _buttonNodes.first.requestFocus();
    }
  }

  bool _focusSelectedTab() {
    final id = _seasonId;
    if (_seasons.length < 2 || id == null) return false;
    _tabNode(id).requestFocus();
    return true;
  }

  void _focusEpisode(AggregatedItem episode) {
    final index = _episodes.indexOf(episode);
    if (index < 0) return;
    final node = _cardNode(episode.id);
    if (node.context == null) {
      // Not built yet: the row only builds what is near the screen.
      _scrollRowTo(index, animate: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cardNode(episode.id).requestFocus();
      });
      return;
    }
    node.requestFocus();
  }

  void _scrollRowTo(int index, {required bool animate}) {
    if (index < 0 || !_rowScroll.hasClients) return;
    final position = _rowScroll.position;
    final extent = _cardWidth + _cardGap;
    final itemLeft = index * extent;
    final viewport = position.viewportDimension;
    // Scroll only as far as needed to show the card whole, as Plex does.
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

  /// Centres [seasonId]'s tab in the tab strip.
  void _revealTab(String seasonId, {required bool animate}) {
    final tabContext = _tabNodes[seasonId]?.context;
    if (tabContext == null) return;
    Scrollable.ensureVisible(
      tabContext,
      alignment: 0.5,
      duration: animate ? _move : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  void _startRowAt(int index) {
    if (index < 0 || !_rowScroll.hasClients) return;
    final position = _rowScroll.position;
    _rowScroll.jumpTo(
      (index * (_cardWidth + _cardGap)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _revealTop() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0, duration: _move, curve: Curves.easeOutCubic);
    }
  }

  // --- Keys ---------------------------------------------------------------

  KeyEventResult _onTabKey(String seasonId, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final index = _seasons.indexWhere((s) => s.id == seasonId);
    final key = event.logicalKey;
    if (isActivateKey(event)) {
      _selectSeasonNow(seasonId);
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      if (index > 0) {
        _tabNode(_seasons[index - 1].id).requestFocus();
      } else {
        NavigationLayout.focusNavbar();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index < _seasons.length - 1) {
        _tabNode(_seasons[index + 1].id).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      _selectSeasonNow(seasonId);
      final focused = _focused;
      if (focused != null && _seasonId == seasonId) _focusEpisode(focused);
      return KeyEventResult.handled;
    }
    if (key.isUpKey) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  void _onTabFocus(String seasonId, bool focused) {
    if (!focused) return;
    _region = _Region.tabs;
    _revealTop();
    _revealTab(seasonId, animate: true);
    // Moving along the tabs shows each season, like Plex, but only once the
    // remote rests, so racing past twenty seasons loads one.
    _seasonDebounce?.cancel();
    _seasonDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _seasonId != seasonId) unawaited(_showSeason(seasonId));
    });
  }

  void _selectSeasonNow(String seasonId) {
    _seasonDebounce?.cancel();
    if (_seasonId != seasonId) {
      _initialFocusDone = false;
      unawaited(_showSeason(seasonId));
    }
  }

  KeyEventResult _onCardKey(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final episodes = _episodes;
    final key = event.logicalKey;
    if (isActivateKey(event)) {
      if (event is KeyDownEvent) _play(episodes[index]);
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      if (index > 0) {
        _focusEpisode(episodes[index - 1]);
      } else {
        NavigationLayout.focusNavbar();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index < episodes.length - 1) _focusEpisode(episodes[index + 1]);
      return KeyEventResult.handled;
    }
    if (key.isUpKey) {
      _focusSelectedTab();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      _buttonNodes[0].requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isContextMenuKey) {
      _showMenu(episodes[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onCardFocus(AggregatedItem episode, bool focused) {
    if (!focused) return;
    _region = _Region.row;
    _revealTop();
    _scrollRowTo(_episodes.indexOf(episode), animate: true);
    if (_focused?.id != episode.id) _focusedNotifier.value = episode;
  }

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
    if (key.isUpKey) {
      final focused = _focused;
      if (focused != null) _focusEpisode(focused);
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      _focusSection(0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Actions ------------------------------------------------------------

  void _pressButton(int index) {
    final episode = _focused;
    if (episode == null) return;
    switch (index) {
      case 0:
        _play(episode);
      case 1:
        unawaited(_toggleWatched(episode));
      default:
        _showMenu(episode);
    }
  }

  void _play(AggregatedItem episode) {
    final actions = _actionsKey.currentState;
    if (actions == null) return;
    unawaited(
      actions
          .playItem(context, episode, resume: _inProgress(episode))
          .catchError((Object e) => debugPrint('[PlexSeasonPage] play: $e')),
    );
  }

  Future<void> _toggleWatched(AggregatedItem episode) async {
    try {
      await GetIt.instance<ItemMutationRepository>().setPlayed(
        episode.id,
        isPlayed: !episode.isPlayed,
      );
    } catch (e) {
      debugPrint('[PlexSeasonPage] watched ${episode.id}: $e');
    }
    await _refreshSeason();
  }

  void _showMenu(AggregatedItem episode) {
    unawaited(
      showContextMenu(
        context,
        episode,
        onChanged: () => unawaited(_refreshSeason()),
      ),
    );
  }

  // --- Sections -----------------------------------------------------------

  /// The page's other sections, in the user's order (Details Screen >
  /// Sections). The episodes are this page's own row, so they stay on top.
  List<({GlobalKey key, Widget child})> _sections() {
    final item = _item;
    if (item == null) return const [];
    final visibility = DetailSectionVisibility.of(widget.prefs);
    final actors = visibility.shows(DetailSection.cast) ? _vm.actors : const <Map<String, dynamic>>[];
    final directors = visibility.shows(DetailSection.crew) ? _vm.directors : const <Map<String, dynamic>>[];
    final writers = visibility.shows(DetailSection.crew) ? _vm.writers : const <Map<String, dynamic>>[];

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
          child: NouveauPeopleSection(
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
      if (visibility.shows(DetailSection.extras) && _vm.features.isNotEmpty)
        (
          key: _extrasKey,
          rank: rank[DetailSection.extras]!,
          child: NouveauExtrasSection(
            key: _extrasKey,
            items: _vm.features,
            imageApi: _vm.imageApi,
            prefs: widget.prefs,
            onNavigateUp: () => _sectionUp(_extrasKey),
            onNavigateDown: () => _sectionDown(_extrasKey),
          ),
        ),
      if (NouveauDiscoverySection.shouldInclude(_vm, visibility))
        (
          key: _discoveryKey,
          rank: rank[DetailSection.moreLikeThis]!,
          child: NouveauDiscoverySection(
            key: _discoveryKey,
            viewModel: _vm,
            prefs: widget.prefs,
            visibility: visibility,
            onNavigateUp: () => _sectionUp(_discoveryKey),
            onNavigateDown: () => _sectionDown(_discoveryKey),
            onRevealRequested: _revealSection,
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

  bool _sectionUp(GlobalKey from) {
    final index = _sectionKeys.indexOf(from);
    if (index <= 0) {
      _revealTop();
      _buttonNodes[_lastButton].requestFocus();
      return true;
    }
    for (var i = index - 1; i >= 0; i--) {
      if (_focusSectionAt(i)) return true;
    }
    _buttonNodes[_lastButton].requestFocus();
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
                SizedBox(height: _foldHeight, child: _buildFold()),
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
        Positioned(
          top: _tabsTop + PlexStyle.s(4),
          right: PlexStyle.s(44),
          child: const PlexClock(),
        ),
        // Only there to play: its playback path queues the rest of the season
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

  Widget _buildFold() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<AggregatedItem?>(
            valueListenable: _focusedNotifier,
            builder: (context, focused, _) =>
                PlexHomeHeader(item: focused, leftInset: _inset),
          ),
        ),
        if (_seasons.length > 1)
          Positioned(
            top: _tabsTop,
            left: 0,
            right: PlexStyle.s(120),
            height: _tabHeight,
            child: _buildTabs(),
          ),
        Positioned(
          top: _rowTop - _cardHeight * (_focusScale - 1) / 2,
          left: 0,
          right: 0,
          height: _cardHeight * _focusScale,
          child: _buildRow(),
        ),
        Positioned(
          top: _buttonsTop,
          left: _inset,
          child: _buildButtons(),
        ),
        Positioned(
          top: _buttonsTop,
          right: _rightInset,
          height: _buttonSize,
          child: ValueListenableBuilder<AggregatedItem?>(
            valueListenable: _focusedNotifier,
            builder: (context, focused, _) => focused == null
                ? const SizedBox.shrink()
                : _MediaChips(episode: focused),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    // Every tab is built (a show has a few dozen at most), so the selected
    // one can always be scrolled to, even before it was ever on screen.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: _inset - PlexStyle.s(8)),
      child: Row(
        children: [
          for (final season in _seasons)
            Focus(
              focusNode: _tabNode(season.id),
              onFocusChange: (f) => _onTabFocus(season.id, f),
              onKeyEvent: (_, event) => _onTabKey(season.id, event),
              child: GestureDetector(
                onTap: () => _selectSeasonNow(season.id),
                child: ListenableBuilder(
                  listenable: _tabNode(season.id),
                  builder: (context, _) => _SeasonTab(
                    label: season.name,
                    selected: season.id == _seasonId,
                    focused: _tabNode(season.id).hasFocus,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow() {
    final episodes = _episodes;
    return ListView.builder(
      controller: _rowScroll,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: EdgeInsets.symmetric(horizontal: _inset),
      itemExtent: _cardWidth + _cardGap,
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final node = _cardNode(episode.id);
        return Align(
          alignment: Alignment.centerLeft,
          child: Focus(
            focusNode: node,
            onFocusChange: (f) => _onCardFocus(episode, f),
            onKeyEvent: (_, event) => _onCardKey(index, event),
            child: GestureDetector(
              onTap: () => _play(episode),
              child: ListenableBuilder(
                listenable: node,
                builder: (context, _) => _EpisodeCard(
                  episode: episode,
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

  Widget _buildButtons() {
    const icons = [Symbols.play_arrow, Symbols.check_circle, Symbols.more_horiz];
    return Row(
      children: [
        for (var i = 0; i < icons.length; i++) ...[
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
                // The Watched check fills in once the focused episode is
                // watched, so that one also follows the focused episode.
                listenable: i == 1
                    ? Listenable.merge([_buttonNodes[i], _focusedNotifier])
                    : _buttonNodes[i],
                builder: (context, _) => _RoundButton(
                  icon: icons[i],
                  filled: i == 1 && (_focused?.isPlayed ?? false),
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
}

class _SeasonTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool focused;

  const _SeasonTab({
    required this.label,
    required this.selected,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: selected || focused ? 1 : 0.6),
      fontSize: PlexStyle.s(12.5),
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: EdgeInsets.symmetric(horizontal: PlexStyle.s(4)),
      padding: EdgeInsets.symmetric(horizontal: PlexStyle.s(10)),
      decoration: BoxDecoration(
        color: focused ? Colors.white.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(PlexStyle.s(4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: style, maxLines: 1),
          SizedBox(height: PlexStyle.s(3)),
          // Plex's gold underline under the season on screen.
          Container(
            height: PlexStyle.s(2),
            width: PlexStyle.s(24),
            color: selected ? PlexStyle.accent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final AggregatedItem episode;
  final ImageApi imageApi;
  final bool focused;

  const _EpisodeCard({
    required this.episode,
    required this.imageApi,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = ArtworkDecode.widthFor(
      _cardWidth * _focusScale,
      dpr,
      layoutHeight: _cardHeight * _focusScale,
      sourceAspectRatio: 16 / 9,
    );
    final url = imageApi.getPrimaryImageUrl(
      episode.id,
      maxWidth: decodeWidth,
      tag: episode.primaryImageTag,
    );
    final number = episode.indexNumber;
    final runtime = episode.runtime;
    final position = episode.playbackPosition;
    final progress =
        !episode.isPlayed &&
            runtime != null &&
            position != null &&
            runtime > Duration.zero &&
            position > Duration.zero
        ? (position.inMilliseconds / runtime.inMilliseconds).clamp(0.0, 1.0)
        : null;
    final radius = BorderRadius.circular(PlexStyle.posterRadius);

    return AnimatedScale(
      scale: focused ? _focusScale : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        width: _cardWidth,
        height: _cardHeight,
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
              if (episode.primaryImageTag != null)
                Image(
                  image: ArtworkDecode.provider(
                    url,
                    width: decodeWidth,
                    headers: artworkFetchHeaders(url, ImageFetchPriority.normal),
                  ),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              if (number != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: _EpisodeBadge(number: number, played: episode.isPlayed),
                ),
              if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: PlexStyle.s(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    color: PlexStyle.accent,
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plex's corner tag: "E3", with a check before it once watched.
class _EpisodeBadge extends StatelessWidget {
  final int number;
  final bool played;

  const _EpisodeBadge({required this.number, required this.played});

  @override
  Widget build(BuildContext context) {
    final size = PlexStyle.s(10);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: PlexStyle.s(5),
        vertical: PlexStyle.s(2),
      ),
      color: Colors.black.withValues(alpha: 0.75),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (played) ...[
            Icon(Icons.check, size: size * 1.2, color: Colors.white),
            SizedBox(width: PlexStyle.s(3)),
          ],
          Text(
            'E$number',
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final bool focused;
  final double size;

  const _RoundButton({
    required this.icon,
    required this.filled,
    required this.focused,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.12),
      ),
      child: Icon(
        icon,
        size: size * 0.55,
        fill: filled ? 1 : 0,
        color: focused ? Colors.black : Colors.white,
      ),
    );
  }
}

/// The focused episode's resolution, audio and subtitle, as Plex shows them
/// at the right of the buttons: "1080p", "English (EAC3 5.1)", "English (SRT)".
class _MediaChips extends StatelessWidget {
  final AggregatedItem episode;

  const _MediaChips({required this.episode});

  @override
  Widget build(BuildContext context) {
    final streams = episode.mediaStreams;
    Map<String, dynamic>? pick(String type) {
      final ofType = streams.where((s) => s['Type'] == type).toList();
      if (ofType.isEmpty) return null;
      return ofType.where((s) => s['IsDefault'] == true).firstOrNull ??
          (type == 'Subtitle' ? null : ofType.first);
    }

    final audio = pick('Audio');
    final subtitle = pick('Subtitle');
    final chips = <Widget>[
      if (episode.videoResolution case final resolution?)
        _Chip(text: resolution),
      if (audio != null)
        _Chip(icon: Icons.volume_up_rounded, text: _streamLabel(audio, audio: true)),
      if (subtitle != null)
        _Chip(icon: Icons.subtitles_outlined, text: _streamLabel(subtitle)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) SizedBox(width: PlexStyle.s(8)),
          chips[i],
        ],
      ],
    );
  }

  /// "English (EAC3 5.1)", "German Forced (PGS)": the language, then the
  /// codec and, for audio, the channel layout.
  static String _streamLabel(Map<String, dynamic> stream, {bool audio = false}) {
    final forced = !audio && stream['IsForced'] == true;
    final language = '${_languageName(stream['Language'] as String?)}'
        '${forced ? ' Forced' : ''}';
    var codec = (stream['Codec'] as String?)?.toUpperCase() ?? '';
    codec = _codecNames[codec] ?? codec;
    final parts = [
      codec,
      if (audio) _layout(stream),
    ].where((p) => p.isNotEmpty).join(' ');
    return parts.isEmpty ? language : '$language ($parts)';
  }

  static const _codecNames = {'SUBRIP': 'SRT', 'PGSSUB': 'PGS'};

  /// The server's DisplayTitle doesn't reliably start with the language (a
  /// track titled "Stereo" puts that first), so the name comes from the code.
  static String _languageName(String? code) {
    final iso3 = toIso3Language(normalizeLanguage(code));
    if (iso3.isEmpty) return 'Unknown';
    final terminology = _bibliographicCodes[iso3] ?? iso3;
    return kIso6392Languages[terminology] ?? iso3.toUpperCase();
  }

  /// Older ISO 639-2/B codes, which files often carry, to the /T codes the
  /// name table uses.
  static const _bibliographicCodes = {
    'alb': 'sqi', 'arm': 'hye', 'baq': 'eus', 'bur': 'mya', 'chi': 'zho',
    'cze': 'ces', 'dut': 'nld', 'fre': 'fra', 'geo': 'kat', 'ger': 'deu',
    'gre': 'ell', 'ice': 'isl', 'mac': 'mkd', 'mao': 'mri', 'may': 'msa',
    'per': 'fas', 'rum': 'ron', 'slo': 'slk', 'tib': 'bod', 'wel': 'cym',
  };

  static String _layout(Map<String, dynamic> stream) {
    final layout = (stream['ChannelLayout'] as String?)?.trim() ?? '';
    if (layout.isNotEmpty) {
      return layout.toLowerCase() == 'stereo' ? 'Stereo' : layout;
    }
    final channels = stream['Channels'];
    if (channels is int) return channels == 2 ? 'Stereo' : '$channels ch';
    return '';
  }
}

class _Chip extends StatelessWidget {
  final IconData? icon;
  final String text;

  const _Chip({this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final size = PlexStyle.s(10);
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: PlexStyle.s(5),
          vertical: PlexStyle.s(2),
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(PlexStyle.s(3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: size * 1.2, color: Colors.white),
              SizedBox(width: PlexStyle.s(4)),
            ],
            Text(
              text,
              maxLines: 1,
              style: TextStyle(color: Colors.white, fontSize: size),
            ),
          ],
        ),
      ),
    );
  }
}
