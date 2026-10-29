import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/repositories/mdblist_repository.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../data/utils/alphabet_bucket.dart';
import '../../data/viewmodels/library_browse_view_model.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/focus/dpad_keys.dart';
import '../navigation/destinations.dart';
import '../navigation/playback_launcher.dart';
import '../navigation/route_lifecycle_observer.dart';
import '../screens/detail/item_detail_screen.dart' show TrackTile;
import '../widgets/focus/context_menu_sheet.dart';
import '../widgets/overlay_sheet.dart';
import 'plex_backdrop.dart';
import 'plex_clock.dart';
import 'plex_nav.dart';
import 'plex_poster.dart';
import 'plex_spinner.dart';
import 'plex_style.dart';

/// Plex's library page (references 09-11), used for every library on TV:
///
/// - tabs along the top: Recommended, Library and, when the library has any,
///   Collections, with the clock top right;
/// - on Library, the filter row: what to show, which type, the sort, and Play
///   and Shuffle on the right;
/// - six posters a row with the title and year centred under each;
/// - the alphabet down the right edge while sorted by title, the focused
///   title's letter in gold;
/// - no art: the page is a wash of the focused title's colours.
///
/// The header and tabs scroll away with the grid; the alphabet stays put.
class PlexLibraryPage extends StatefulWidget {
  final String libraryId;
  final String? serverId;

  const PlexLibraryPage({super.key, required this.libraryId, this.serverId});

  /// Whether [uri] opens this page (app_router.dart): a whole library or
  /// music library. A type or favourites view of one keeps the upstream grid,
  /// and so do its sub-pages (genres, letters).
  static bool handles(Uri uri) {
    if (!PlexStyle.enabled) return false;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 2) return false;
    if (segments.first == 'music') return true;
    final query = uri.queryParameters;
    return segments.first == 'library' &&
        !query.containsKey('types') &&
        query['favorites'] != '1';
  }

  @override
  State<PlexLibraryPage> createState() => _PlexLibraryPageState();
}

enum _Tab { recommended, library, collections }

enum _Kind { movies, shows, music, other }

/// One entry of the type menu: what the grid asks the server for and how its
/// artwork is shaped.
class _TypeOption {
  final List<String>? types;
  final double aspectRatio;
  final int columns;

  const _TypeOption(this.types, {this.aspectRatio = 2 / 3, this.columns = 6});

  bool get isTracks => types?.contains('Audio') ?? false;
}

const _typeOptions = <_Kind, List<_TypeOption>>{
  _Kind.movies: [_TypeOption(null)],
  _Kind.shows: [
    _TypeOption(null),
    _TypeOption(['Season']),
    _TypeOption(['Episode'], aspectRatio: 16 / 9, columns: 4),
  ],
  _Kind.music: [
    _TypeOption(['AlbumArtist'], aspectRatio: 1),
    _TypeOption(['MusicAlbum'], aspectRatio: 1),
    _TypeOption(['Audio']),
  ],
  _Kind.other: [_TypeOption(null)],
};

/// Plex's sort names for the options it shares with Moonfin, in Plex's order.
const _plexSorts = <LibrarySortBy, String>{
  LibrarySortBy.name: 'Title',
  LibrarySortBy.premiereDate: 'Release Date',
  LibrarySortBy.criticRating: 'Critic Rating',
  LibrarySortBy.communityRating: 'Audience Rating',
  LibrarySortBy.rating: 'Content Rating',
  LibrarySortBy.runtime: 'Duration',
  LibrarySortBy.playCount: 'Plays',
  LibrarySortBy.dateAdded: 'Date Added',
  LibrarySortBy.dateEpisodeAdded: 'Last Episode Date Added',
  LibrarySortBy.datePlayed: 'Date Viewed',
  LibrarySortBy.albumArtist: 'Artist',
  LibrarySortBy.album: 'Album',
  LibrarySortBy.random: 'Randomly',
};

/// A Recommended row.
class _Hub {
  final String title;
  final List<AggregatedItem> items;

  const _Hub(this.title, this.items);
}

/// The alphabet letter [item] files under: its first letter once accents fold
/// away, `#` for anything starting otherwise, null for no name at all.
String? plexLibraryLetter(AggregatedItem item) {
  final key = alphabetSortKey(item);
  if (key.isEmpty) return null;
  final first = key[0];
  return RegExp('[A-Z]').hasMatch(first) ? first : '#';
}

/// The two lines under a library card, as Plex words them: a title and its
/// year; a show and season; a show and "S1 · E3"; an album and its artist.
(String, String?) plexLibraryCaptions(
  AggregatedItem item, {
  required String Function(int count) itemCount,
}) {
  return switch (item.type) {
    'Season' => (item.seriesName ?? item.name, item.name),
    'Episode' => (
      item.seriesName ?? item.name,
      'S${item.parentIndexNumber ?? 0} · E${item.indexNumber ?? 0}',
    ),
    'MusicAlbum' => (
      item.name,
      item.albumArtist ?? (item.artists.isEmpty ? null : item.artists.first),
    ),
    'MusicArtist' || 'AlbumArtist' => (item.name, null),
    'BoxSet' => (
      item.name,
      item.childCount == null ? null : itemCount(item.childCount!),
    ),
    _ => (item.name, item.productionYear?.toString()),
  };
}

/// Where the page was last left in each library, for this session: Plex
/// reopens a library on the tab and type it was on.
final _lastTab = <String, _Tab>{};
final _lastType = <String, int>{};

class _PlexLibraryPageState extends State<PlexLibraryPage> with RouteAware {
  late final MediaServerClient _client;
  final _prefs = GetIt.instance<UserPreferences>();
  final _scroll = ScrollController();

  _Kind? _kind;
  _Tab _tab = _Tab.library;
  int _typeIndex = 0;
  LibraryBrowseViewModel? _vm;

  List<AggregatedItem> _collections = const [];
  List<_Hub>? _hubs;
  bool _hubsLoading = false;

  final _tintUrl = ValueNotifier<String?>(null);
  final _activeLetter = ValueNotifier<String?>(null);
  Timer? _tintDebounce;

  final _tabNodes = {
    for (final tab in _Tab.values) tab: FocusNode(debugLabel: 'plex-tab-$tab'),
  };

  /// Filter, type, sort, Play, Shuffle.
  final _barNodes = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'plex-library-bar-$i'),
  );
  final _letterNodes = List.generate(
    _letters.length,
    (i) => FocusNode(debugLabel: 'plex-letter-${_letters[i]}'),
  );
  final _gridNodes = <FocusNode>[];
  final _hubKeys = <GlobalKey<_HubRowState>>[];

  /// The grid card focus last sat on, for coming back from the bar above or
  /// the alphabet beside it.
  int _lastGridIndex = 0;

  /// A card below the loaded rows that Down asked for; focused once its page
  /// arrives.
  int? _pendingFocus;
  bool _openedOnFirstTitle = false;
  ModalRoute<dynamic>? _observedRoute;

  static const _letters = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  // Plex's measurements (960-wide, see PlexStyle), from the rail's edge.
  static final _tabsLeft = PlexStyle.s(40);
  static final _barLeft = PlexStyle.s(20);
  static final _barRight = PlexStyle.s(80);
  static final _barTop = PlexStyle.s(80);
  static final _barHeight = PlexStyle.s(32);
  static final _headerHeight = PlexStyle.s(140);
  static final _gridGap = PlexStyle.s(17);
  static final _rowStride = PlexStyle.s(245);
  static final _posterWidth = PlexStyle.s(120);

  /// Where Plex holds the focused row once the page has scrolled.
  static final _focusedRowTop = PlexStyle.s(160);

  _TypeOption get _type => _typeOptions[_kind ?? _Kind.other]![_typeIndex];

  List<AggregatedItem> get _gridItems => switch (_tab) {
    _Tab.collections => _collections,
    _ => _vm?.items ?? const [],
  };

  int get _columns => _tab == _Tab.collections ? 6 : _type.columns;

  double get _aspectRatio =>
      _tab == _Tab.collections ? 2 / 3 : _type.aspectRatio;

  bool get _showsLetters =>
      _tab == _Tab.library &&
      !_type.isTracks &&
      _vm?.state == LibraryBrowseState.ready &&
      _vm?.sortBy == LibrarySortBy.name;

  List<String> get _letterOrder =>
      _vm?.sortDirection == SortDirection.descending
      ? _letters.reversed.toList()
      : _letters;

  @override
  void initState() {
    super.initState();
    _client = GetIt.instance<MediaServerClientFactory>()
        .clientForServerOrActive(widget.serverId);
    _tab = _lastTab[widget.libraryId] ?? _Tab.library;
    _typeIndex = _lastType[widget.libraryId] ?? 0;
    unawaited(_resolveKind());
    InlineBackInterceptor.push(_onBack);
  }

  /// Back from deep in the grid returns to its first title, and from a
  /// Recommended row to the tabs, before it leaves the page. It has to run
  /// ahead of the app's own Back, which pops the page before the focused
  /// card ever sees the key.
  bool _onBack() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final gridIndex = _gridNodes.indexOf(focus);
    if (gridIndex >= _columns) {
      _focusCard(0, animate: false);
      return true;
    }
    final inHubRow =
        focus.context?.findAncestorStateOfType<_HubRowState>() != null;
    if (_tab == _Tab.recommended && inHubRow) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _tabNodes[_tab]!.requestFocus();
      return true;
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    unawaited(_vm?.syncUserDataIfStale());
  }

  @override
  void dispose() {
    InlineBackInterceptor.remove(_onBack);
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _tintDebounce?.cancel();
    _vm?.removeListener(_onVm);
    _vm?.dispose();
    _scroll.dispose();
    _tintUrl.dispose();
    _activeLetter.dispose();
    for (final node in [
      ..._tabNodes.values,
      ..._barNodes,
      ..._letterNodes,
      ..._gridNodes,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _resolveKind() async {
    var kind = _Kind.other;
    try {
      final data = await _client.itemsApi.getItem(widget.libraryId, fields: '');
      kind = switch ((data['CollectionType'] as String?)?.toLowerCase()) {
        'movies' => _Kind.movies,
        'tvshows' => _Kind.shows,
        'music' => _Kind.music,
        _ => _Kind.other,
      };
    } catch (e) {
      debugPrint('[PlexLibrary] library type: $e');
    }
    if (!mounted) return;
    setState(() {
      _kind = kind;
      if (_typeIndex >= _typeOptions[kind]!.length) _typeIndex = 0;
      if (kind == _Kind.music || kind == _Kind.other) {
        if (_tab == _Tab.collections) _tab = _Tab.library;
      }
    });
    _createViewModel();
    if (_tab == _Tab.recommended) unawaited(_loadHubs());
    if (kind == _Kind.movies || kind == _Kind.shows) {
      unawaited(_loadCollections());
    }
  }

  void _createViewModel() {
    final old = _vm;
    old?.removeListener(_onVm);
    old?.dispose();
    _resetGridNodes();
    _pendingFocus = null;
    final vm = LibraryBrowseViewModel(
      libraryId: widget.libraryId,
      client: _client,
      prefs: _prefs,
      mdbListRepository: GetIt.instance<MdbListRepository>(),
      includeItemTypes: _type.types,
      // The filter menu here offers watched status and favorites only.
      statusFiltersOnly: true,
    );
    vm.addListener(_onVm);
    _vm = vm;
    unawaited(vm.load());
  }

  void _onVm() {
    if (!mounted) return;
    setState(() {});
    final vm = _vm;
    if (vm == null || _tab != _Tab.library) return;
    final pending = _pendingFocus;
    if (pending != null && !vm.loadingMore) {
      _pendingFocus = null;
      if (vm.items.isNotEmpty) {
        _focusCard(pending.clamp(0, vm.items.length - 1));
      }
    }
    _maybeOpenOnFirstTitle();
  }

  /// Whether focus is somewhere on this page, not on the rail or nowhere yet.
  bool get _focusOnPage {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        focused.findAncestorStateOfType<_PlexLibraryPageState>() == this;
  }

  /// A library opens on its first title, as in Plex (user, 2026-10-23), unless
  /// the user has already moved somewhere on the page.
  void _maybeOpenOnFirstTitle() {
    if (_openedOnFirstTitle || _gridItems.isEmpty) return;
    _openedOnFirstTitle = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      // The rail hands focus to the first tab as the page opens; that is
      // where the page was left, not a choice the user made.
      final onTab = _tabNodes.values.any((node) => node.hasPrimaryFocus);
      if (!_focusOnPage || onTab) _focusCard(0, animate: false);
    });
  }

  Future<void> _loadCollections() async {
    try {
      final response = await _client.itemsApi.getItems(
        parentId: widget.libraryId,
        includeItemTypes: const ['BoxSet'],
        recursive: true,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        limit: 500,
        fields: _itemFields,
        enableImageTypes: 'Primary,Backdrop',
        imageTypeLimit: 1,
      );
      if (!mounted) return;
      setState(() => _collections = _mapItems(response));
      // Reopened on Collections: its first title takes focus, as on Library.
      if (_tab == _Tab.collections) _maybeOpenOnFirstTitle();
    } catch (e) {
      debugPrint('[PlexLibrary] collections: $e');
    }
  }

  static const _itemFields =
      'PrimaryImageAspectRatio,SortName,Type,UserData,ProductionYear,'
      'ImageTags,BackdropImageTags,ParentBackdropItemId,'
      'ParentBackdropImageTags,SeriesId,SeriesName,SeriesPrimaryImageTag,'
      'ParentIndexNumber,IndexNumber,ChildCount,AlbumArtist,Artists,'
      'AlbumId,AlbumPrimaryImageTag,RunTimeTicks';

  List<AggregatedItem> _mapItems(Map<String, dynamic> response) {
    final raw = response['Items'] as List? ?? const [];
    return [
      for (final entry in raw.whereType<Map>())
        AggregatedItem(
          id: entry['Id']?.toString() ?? '',
          serverId: _client.baseUrl,
          rawData: entry.cast<String, dynamic>(),
        ),
    ];
  }

  Future<void> _loadHubs() async {
    if (_hubsLoading || _hubs != null) return;
    _hubsLoading = true;
    final l10n = AppLocalizations.of(context);
    final id = widget.libraryId;
    final api = _client.itemsApi;
    Future<_Hub?> hub(String title, Future<Map<String, dynamic>> query) async {
      try {
        final items = _mapItems(await query);
        return items.isEmpty ? null : _Hub(title, items);
      } catch (e) {
        debugPrint('[PlexLibrary] $title: $e');
        return null;
      }
    }

    const limit = 24;
    final queries = <Future<_Hub?>>[
      if (_kind == _Kind.movies) ...[
        hub(
          l10n.continueWatching,
          api.getResumeItems(
            parentId: id,
            includeItemTypes: const ['Movie'],
            limit: limit,
            fields: _itemFields,
          ),
        ),
        hub(
          l10n.recentlyReleased,
          api.getRecentlyReleasedItems(
            parentId: id,
            includeItemTypes: const ['Movie'],
            limit: limit,
            fields: _itemFields,
            recursive: true,
          ),
        ),
        hub(
          l10n.recentlyAdded,
          api.getLatestItems(
            parentId: id,
            includeItemTypes: const ['Movie'],
            limit: limit,
            fields: _itemFields,
          ),
        ),
      ] else if (_kind == _Kind.shows) ...[
        hub(
          l10n.continueWatching,
          api.getResumeItems(
            parentId: id,
            includeItemTypes: const ['Episode'],
            limit: limit,
            fields: _itemFields,
          ),
        ),
        hub(
          l10n.nextUp,
          api.getNextUp(parentId: id, limit: limit, fields: _itemFields),
        ),
        hub(
          l10n.recentlyAdded,
          api.getItems(
            parentId: id,
            includeItemTypes: const ['Series'],
            recursive: true,
            sortBy: 'DateLastContentAdded',
            sortOrder: 'Descending',
            limit: limit,
            fields: _itemFields,
          ),
        ),
        hub(
          l10n.recentlyReleased,
          api.getRecentlyReleasedItems(
            parentId: id,
            includeItemTypes: const ['Episode'],
            limit: limit,
            fields: _itemFields,
            recursive: true,
          ),
        ),
      ] else if (_kind == _Kind.music) ...[
        hub(
          l10n.recentlyAdded,
          api.getLatestItems(
            parentId: id,
            includeItemTypes: const ['MusicAlbum'],
            limit: limit,
            fields: _itemFields,
          ),
        ),
        hub(
          l10n.lastPlayed,
          api.getItems(
            parentId: id,
            includeItemTypes: const ['MusicAlbum'],
            recursive: true,
            sortBy: 'DatePlayed',
            sortOrder: 'Descending',
            filters: const ['IsPlayed'],
            limit: limit,
            fields: _itemFields,
          ),
        ),
      ] else
        hub(
          l10n.recentlyAdded,
          api.getLatestItems(parentId: id, limit: limit, fields: _itemFields),
        ),
    ];
    final hubs = (await Future.wait(queries)).whereType<_Hub>().toList();
    _hubsLoading = false;
    if (!mounted) return;
    setState(() {
      _hubs = hubs;
      _hubKeys
        ..clear()
        ..addAll([for (final _ in hubs) GlobalKey<_HubRowState>()]);
    });
    if (_tab == _Tab.recommended && hubs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusOnPage) _hubKeys.first.currentState?.focusAt(0);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Tabs, type and sort.

  void _selectTab(_Tab tab) {
    if (tab == _tab) return;
    _lastTab[widget.libraryId] = tab;
    setState(() {
      _tab = tab;
      _resetGridNodes();
      _activeLetter.value = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (tab == _Tab.recommended) unawaited(_loadHubs());
  }

  void _selectType(int index) {
    if (index == _typeIndex) return;
    _lastType[widget.libraryId] = index;
    setState(() => _typeIndex = index);
    _createViewModel();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _resetGridNodes() {
    // The cards holding these only let go of them on the next build.
    final old = List.of(_gridNodes);
    _gridNodes.clear();
    _lastGridIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in old) {
        node.dispose();
      }
    });
  }

  FocusNode _gridNode(int index) {
    while (_gridNodes.length <= index) {
      _gridNodes.add(FocusNode(debugLabel: 'plex-card-${_gridNodes.length}'));
    }
    return _gridNodes[index];
  }

  List<_Tab> get _visibleTabs => [
    _Tab.recommended,
    _Tab.library,
    if (_collections.isNotEmpty) _Tab.collections,
  ];

  String _tabLabel(AppLocalizations l10n, _Tab tab) => switch (tab) {
    // Plex's own word; Moonfin has no translation of it yet.
    _Tab.recommended => 'Recommended',
    _Tab.library => l10n.library,
    _Tab.collections => l10n.collections,
  };

  String _typeLabel(AppLocalizations l10n, int index) => switch (_kind) {
    _Kind.movies => l10n.movies,
    _Kind.shows => [l10n.tvShows, l10n.seasons, l10n.episodes][index],
    _Kind.music => [l10n.artists, l10n.albums, l10n.songs][index],
    _ => _vm?.libraryName ?? '',
  };

  String _filterLabel(AppLocalizations l10n) {
    final vm = _vm;
    if (vm == null) return l10n.all;
    if (vm.favoriteFilter) return l10n.favorites;
    return switch (vm.playedFilter) {
      PlayedStatusFilter.all => l10n.all,
      PlayedStatusFilter.unwatched => l10n.unwatched,
      PlayedStatusFilter.watched => l10n.watched,
      PlayedStatusFilter.inProgress => l10n.filterInProgress,
    };
  }

  List<LibrarySortBy> get _sortOptions {
    final offered = _vm?.sortOptions ?? const <LibrarySortBy>[];
    return [
      for (final sort in _plexSorts.keys)
        if (offered.contains(sort)) sort,
    ];
  }

  String _sortLabel(LibrarySortBy sort) => _plexSorts[sort] ?? sort.displayName;

  Future<void> _openFilterMenu(BuildContext anchor) async {
    final vm = _vm;
    if (vm == null) return;
    final l10n = AppLocalizations.of(context);
    final options = [
      (l10n.all, PlayedStatusFilter.all, false),
      (l10n.unwatched, PlayedStatusFilter.unwatched, false),
      (l10n.filterInProgress, PlayedStatusFilter.inProgress, false),
      (l10n.watched, PlayedStatusFilter.watched, false),
      (l10n.favorites, PlayedStatusFilter.all, true),
    ];
    final selected = options.indexWhere(
      (o) => vm.favoriteFilter ? o.$3 : !o.$3 && o.$2 == vm.playedFilter,
    );
    final picked = await _showMenu(anchor, [
      for (final o in options) o.$1,
    ], selected: selected);
    if (picked == null || !mounted || vm != _vm) return;
    final option = options[picked];
    if (vm.favoriteFilter != option.$3) await vm.setFavoriteFilter(option.$3);
    await vm.setPlayedFilter(option.$2);
  }

  Future<void> _openTypeMenu(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context);
    final count = _typeOptions[_kind ?? _Kind.other]!.length;
    final picked = await _showMenu(anchor, [
      for (var i = 0; i < count; i++) _typeLabel(l10n, i),
    ], selected: _typeIndex);
    if (picked != null && mounted) _selectType(picked);
  }

  Future<void> _openSortMenu(BuildContext anchor) async {
    final vm = _vm;
    if (vm == null) return;
    final sorts = _sortOptions;
    final selected = sorts.indexOf(vm.sortBy);
    final picked = await _showMenu(
      anchor,
      [for (final sort in sorts) _sortLabel(sort)],
      selected: selected,
      // Plex marks the active sort with its direction; picking it again turns
      // the order round.
      selectedIcon: vm.sortDirection == SortDirection.ascending
          ? Symbols.arrow_upward
          : Symbols.arrow_downward,
    );
    if (picked == null || !mounted || vm != _vm) return;
    if (picked == selected) {
      await vm.toggleSortDirection();
    } else {
      await vm.setSortBy(sorts[picked]);
    }
  }

  Future<int?> _showMenu(
    BuildContext anchor,
    List<String> labels, {
    required int selected,
    IconData selectedIcon = Symbols.check,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final box = anchor.findRenderObject() as RenderBox?;
    final space = navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || space == null) return Future.value();
    final topLeft = box.localToGlobal(Offset.zero, ancestor: space);
    return showGeneralDialog<int>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      transitionDuration: PlexMotion.fade,
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (_, _, _) => _PlexMenu(
        anchor: topLeft & box.size,
        labels: labels,
        selected: selected,
        selectedIcon: selectedIcon,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Play and Shuffle.

  Future<void> _play({required bool shuffle}) async {
    final vm = _vm;
    final kind = _kind;
    if (vm == null || kind == null) return;
    final types = switch (kind) {
      _Kind.movies => const ['Movie'],
      _Kind.shows => const ['Episode'],
      _Kind.music => const ['Audio'],
      _Kind.other => const ['Movie', 'Episode', 'Video', 'MusicVideo'],
    };
    final String sortBy;
    if (shuffle) {
      sortBy = 'Random';
    } else if (kind == _Kind.shows) {
      sortBy = 'SeriesSortName,ParentIndexNumber,IndexNumber';
    } else {
      sortBy = vm.sortBy.apiValue;
    }
    final filters = switch (vm.playedFilter) {
      PlayedStatusFilter.unwatched => const ['IsUnplayed'],
      PlayedStatusFilter.watched => const ['IsPlayed'],
      PlayedStatusFilter.inProgress => const ['IsResumable'],
      PlayedStatusFilter.all => const <String>[],
    };
    List<AggregatedItem> items;
    try {
      items = _mapItems(
        await _client.itemsApi.getItems(
          parentId: widget.libraryId,
          includeItemTypes: types,
          recursive: true,
          sortBy: sortBy,
          sortOrder: shuffle || kind == _Kind.shows
              ? 'Ascending'
              : vm.sortDirection.apiValue,
          filters: [...filters, if (vm.favoriteFilter) 'IsFavorite'],
          limit: 200,
          fields: _itemFields,
        ),
      );
    } catch (e) {
      debugPrint('[PlexLibrary] play: $e');
      return;
    }
    if (items.isEmpty || !mounted) return;
    final manager = GetIt.instance<PlaybackManager>();
    if (kind == _Kind.music) {
      await manager.playItems(items);
      if (mounted) unawaited(context.push(Destinations.audioPlayer));
      return;
    }
    await launchPlayerWhilePreparing(
      context,
      manager: manager,
      destination: Destinations.videoPlayer,
      startPlayback: (session) async {
        await runPlaybackStart(session, () => manager.playItems(items));
        return true;
      },
    );
  }

  Future<void> _playTracksFrom(int index) async {
    final vm = _vm;
    if (vm == null) return;
    await GetIt.instance<PlaybackManager>().playItems(
      vm.items,
      startIndex: index,
    );
    if (mounted) unawaited(context.push(Destinations.audioPlayer));
  }

  // ---------------------------------------------------------------------------
  // Opening items and following focus.

  void _open(AggregatedItem item) {
    final vm = _vm;
    if (vm != null && vm.isNavigableFolder(item)) {
      context.push(Destinations.folder(item.id));
      return;
    }
    context
        .push(
          Destinations.itemOrPhoto(
            item.id,
            serverId: item.serverId,
            type: item.type,
            // Plex: a show picked in its library opens on its seasons.
            showOverview: item.type == 'Series',
          ),
        )
        .then((result) {
          if (result == true && mounted) unawaited(_vm?.load());
        });
  }

  void _menu(AggregatedItem item) => unawaited(
    showContextMenu(context, item, onChanged: () => setState(() {})),
  );

  /// The page's colour follows the focused title once focus settles there:
  /// holding the remote walks the grid a card at a time.
  void _followFocus(AggregatedItem item) {
    _activeLetter.value = _letterOf(item);
    _tintDebounce?.cancel();
    _tintDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _tintUrl.value = _tintUrlFor(item);
    });
  }

  String? _letterOf(AggregatedItem item) => plexLibraryLetter(item);

  String? _tintUrlFor(AggregatedItem item) {
    final api = _client.imageApi;
    if (item.backdropImageTags.isNotEmpty) {
      return api.getBackdropImageUrl(
        item.id,
        maxWidth: 780,
        tag: item.backdropImageTags.first,
      );
    }
    final parent = item.parentBackdropItemId;
    if (parent != null && item.parentBackdropImageTags.isNotEmpty) {
      return api.getBackdropImageUrl(
        parent,
        maxWidth: 780,
        tag: item.parentBackdropImageTags.first,
      );
    }
    final tag = item.primaryImageTag;
    return tag == null
        ? null
        : api.getPrimaryImageUrl(item.id, maxWidth: 400, tag: tag);
  }

  String? _imageUrl(AggregatedItem item, double width, double aspectRatio) {
    final api = _client.imageApi;
    final decode = PlexPosterCard.decodeWidth(context, width);
    final seriesId = item.seriesId;
    final seriesTag = item.seriesPrimaryImageTag;
    // Episodes in a portrait row wear their show's poster, as on home.
    if (item.type == 'Episode' && aspectRatio < 1 && seriesId != null) {
      if (seriesTag != null) {
        return api.getPrimaryImageUrl(
          seriesId,
          maxWidth: decode,
          tag: seriesTag,
        );
      }
    }
    final tag = item.primaryImageTag;
    if (tag != null) {
      return api.getPrimaryImageUrl(item.id, maxWidth: decode, tag: tag);
    }
    if (seriesId != null && seriesTag != null) {
      return api.getPrimaryImageUrl(seriesId, maxWidth: decode, tag: seriesTag);
    }
    final albumId = item.albumId;
    final albumTag = item.albumPrimaryImageTag;
    if (albumId != null && albumTag != null) {
      return api.getPrimaryImageUrl(albumId, maxWidth: decode, tag: albumTag);
    }
    if (item.backdropImageTags.isNotEmpty) {
      return api.getBackdropImageUrl(
        item.id,
        maxWidth: decode,
        tag: item.backdropImageTags.first,
      );
    }
    return null;
  }

  (String, String?) _captions(AggregatedItem item) => plexLibraryCaptions(
    item,
    itemCount: AppLocalizations.of(context).itemCountLabel,
  );

  // ---------------------------------------------------------------------------
  // Focus movement.

  /// The page's width beside the rail, from the last layout.
  double _contentWidth = PlexStyle.s(920);

  /// Row to row in the grid as last laid out (artwork, captions and gap).
  double _stride = _rowStride;

  double _rowOffset(int row) => _headerHeight + row * _stride - _focusedRowTop;

  void _scrollToRow(int row, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    var target = row == 0 ? 0.0 : _rowOffset(row).clamp(0.0, double.infinity);
    // The grid knows its full height, so the end is a real limit.
    if (position.hasContentDimensions && target > position.maxScrollExtent) {
      target = position.maxScrollExtent;
    }
    if ((target - position.pixels).abs() < 1) return;
    // A far jump (a letter) goes straight there; a neighbouring row glides.
    final far = (target - position.pixels).abs() > _stride * 2.5;
    if (!animate || far) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: PlexMotion.move,
          curve: PlexMotion.curve,
        ),
      );
    }
  }

  void _focusCard(int index, {bool animate = true}) {
    _scrollToRow(index ~/ _columns, animate: animate);
    final node = _gridNode(index);
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    // Not built yet (a letter jump, a new page): after the frame that builds
    // it. That frame has to be asked for, since a move that scrolls nothing
    // schedules none.
    void attempt(int triesLeft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final node = _gridNode(index);
        if (node.context != null) {
          node.requestFocus();
        } else if (triesLeft > 0) {
          attempt(triesLeft - 1);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    }

    attempt(3);
  }

  void _onCardFocus(int index, AggregatedItem item) {
    _lastGridIndex = index;
    _followFocus(item);
    _scrollToRow(index ~/ _columns);
    final vm = _vm;
    if (_tab == _Tab.library &&
        vm != null &&
        vm.hasMore &&
        !vm.loadingMore &&
        index >= vm.items.length - _columns * 2) {
      unawaited(vm.loadMore());
    }
  }

  KeyEventResult _onCardKey(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final count = _gridItems.length;
    final columns = _columns;
    final column = index % columns;
    if (key.isLeftKey) {
      if (column == 0) {
        plexFocusRailFromEdge();
      } else {
        _focusCard(index - 1);
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (column == columns - 1 || index == count - 1) {
        if (_showsLetters) _focusLetter(_activeLetter.value);
      } else {
        _focusCard(index + 1);
      }
      return KeyEventResult.handled;
    }
    if (key.isUpKey) {
      if (index < columns) {
        _focusAboveGrid();
      } else {
        _focusCard(index - columns);
      }
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      final below = index + columns;
      final lastRow = (count - 1) ~/ columns;
      final vm = _vm;
      if (below < count) {
        _focusCard(below);
      } else if (index ~/ columns < lastRow) {
        // A short last row: Plex lands on its last title.
        _focusCard(count - 1);
      } else if (_tab == _Tab.library && vm != null && vm.hasMore) {
        _pendingFocus = below;
        if (!vm.loadingMore) unawaited(vm.loadMore());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusAboveGrid() {
    if (_tab == _Tab.library) {
      _barNodes.first.requestFocus();
    } else {
      _tabNodes[_tab]!.requestFocus();
    }
  }

  void _focusBelowBar() {
    final count = _gridItems.length;
    if (count == 0) return;
    _focusCard(
      _lastGridIndex < _columns ? _lastGridIndex.clamp(0, count - 1) : 0,
    );
  }

  void _focusBelowTabs() {
    switch (_tab) {
      case _Tab.library:
        _barNodes.first.requestFocus();
      case _Tab.collections:
        if (_collections.isNotEmpty) _focusCard(0);
      case _Tab.recommended:
        if (_hubKeys.isNotEmpty) _hubKeys.first.currentState?.focusAt(0);
    }
  }

  void _focusLetter(String? letter) {
    final order = _letterOrder;
    final at = letter == null
        ? 0
        : order.indexOf(letter).clamp(0, order.length - 1);
    _letterNodes[_letters.indexOf(order[at])].requestFocus();
  }

  Future<void> _jumpToLetter(String letter) async {
    final vm = _vm;
    if (vm == null) return;
    await vm
        .ensureItemsLoadedForPrefix(letter)
        .timeout(const Duration(seconds: 15), onTimeout: () => false);
    if (!mounted || vm != _vm) return;
    final items = vm.items;
    var index = items.indexWhere((item) => matchesAlphabetBucket(item, letter));
    if (index < 0) {
      // No title under this letter: the next one along that has any.
      final order = _letterOrder;
      for (final next in order.skip(order.indexOf(letter) + 1)) {
        index = items.indexWhere((item) => matchesAlphabetBucket(item, next));
        if (index >= 0) break;
      }
    }
    if (index >= 0) _focusCard(index, animate: false);
  }

  // ---------------------------------------------------------------------------
  // Building.

  @override
  Widget build(BuildContext context) {
    return plexNavShell(
      background: PlexStyle.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<String?>(
              valueListenable: _tintUrl,
              builder: (_, url, _) => PlexBackdrop(url: url, showArt: false),
            ),
          ),
          // A box LayoutBuilder reruns only when the width changes (the rail
          // opening). A SliverLayoutBuilder in the grid reran on every scroll
          // frame, since a sliver's constraints carry the scroll offset, and
          // rebuilt every visible card each frame.
          LayoutBuilder(
            builder: (context, constraints) {
              _contentWidth = constraints.maxWidth;
              return CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context)),
                  ..._buildContent(context),
                  SliverToBoxAdapter(child: SizedBox(height: PlexStyle.s(60))),
                ],
              );
            },
          ),
          if (_showsLetters) _buildLetters(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = _visibleTabs;
    return SizedBox(
      height: _tab == _Tab.recommended ? PlexStyle.s(80) : _headerHeight,
      child: Stack(
        children: [
          Positioned(
            left: _tabsLeft,
            top: PlexStyle.s(18),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: EdgeInsets.only(right: PlexStyle.s(30)),
                    child: _PlexTab(
                      label: _tabLabel(l10n, tabs[i]),
                      active: tabs[i] == _tab,
                      focusNode: _tabNodes[tabs[i]]!,
                      onSelect: () => _selectTab(tabs[i]),
                      onKey: (event) {
                        if (!event.isActionable) return false;
                        final key = event.logicalKey;
                        if (key.isLeftKey) {
                          if (i == 0) {
                            plexFocusRailFromEdge();
                          } else {
                            _tabNodes[tabs[i - 1]]!.requestFocus();
                          }
                          return true;
                        }
                        if (key.isRightKey) {
                          if (i < tabs.length - 1) {
                            _tabNodes[tabs[i + 1]]!.requestFocus();
                          }
                          return true;
                        }
                        if (key.isDownKey) {
                          _focusBelowTabs();
                          return true;
                        }
                        return key.isUpKey;
                      },
                    ),
                  ),
              ],
            ),
          ),
          PlexClock.corner(),
          if (_tab == _Tab.library && _vm != null)
            Positioned(
              left: _barLeft,
              right: _barRight,
              top: _barTop,
              height: _barHeight,
              child: _buildBar(l10n),
            ),
        ],
      ),
    );
  }

  Widget _buildBar(AppLocalizations l10n) {
    final vm = _vm!;
    final types = _typeOptions[_kind ?? _Kind.other]!;
    final showType = _kind != _Kind.other;
    final showSort = !_type.isTracks && _sortOptions.isNotEmpty;
    // The order Left and Right walk.
    final order = [0, if (showType) 1, if (showSort) 2, 3, 4];
    bool onKey(int slot, KeyEvent event) {
      if (!event.isActionable) return false;
      final key = event.logicalKey;
      final at = order.indexOf(slot);
      if (key.isLeftKey) {
        if (at == 0) {
          plexFocusRailFromEdge();
        } else {
          _barNodes[order[at - 1]].requestFocus();
        }
        return true;
      }
      if (key.isRightKey) {
        if (at < order.length - 1) _barNodes[order[at + 1]].requestFocus();
        return true;
      }
      if (key.isUpKey) {
        _tabNodes[_tab]!.requestFocus();
        return true;
      }
      if (key.isDownKey) {
        _focusBelowBar();
        return true;
      }
      return false;
    }

    Widget dropdown(int slot, String label, void Function(BuildContext) open) =>
        Builder(
          builder: (anchor) => _PlexBarButton(
            focusNode: _barNodes[slot],
            onKey: (event) => onKey(slot, event),
            onTap: () => open(anchor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _barText(label),
                SizedBox(width: PlexStyle.s(10)),
                const _Caret(),
              ],
            ),
          ),
        );

    return Row(
      children: [
        dropdown(0, _filterLabel(l10n), _openFilterMenu),
        if (showType) ...[
          SizedBox(width: PlexStyle.s(8)),
          dropdown(
            1,
            _typeLabel(l10n, _typeIndex.clamp(0, types.length - 1)),
            _openTypeMenu,
          ),
        ],
        if (showSort) ...[
          SizedBox(width: PlexStyle.s(18)),
          Text(
            'by',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: PlexStyle.s(12.5),
            ),
          ),
          SizedBox(width: PlexStyle.s(18)),
          dropdown(2, _sortLabel(vm.sortBy), _openSortMenu),
        ],
        const Spacer(),
        _PlexBarButton(
          focusNode: _barNodes[3],
          square: true,
          onKey: (event) => onKey(3, event),
          onTap: () => unawaited(_play(shuffle: false)),
          child: const _BarIcon(Symbols.play_arrow, fill: true),
        ),
        SizedBox(width: PlexStyle.s(16)),
        _PlexBarButton(
          focusNode: _barNodes[4],
          square: true,
          onKey: (event) => onKey(4, event),
          onTap: () => unawaited(_play(shuffle: true)),
          child: const _BarIcon(Symbols.shuffle),
        ),
      ],
    );
  }

  static Widget _barText(String text) => _BarLabel(text);

  List<Widget> _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget message(Widget child) => SliverToBoxAdapter(
      child: SizedBox(
        height: PlexStyle.s(300),
        child: Center(child: child),
      ),
    );
    final text = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: PlexStyle.s(13),
    );

    if (_tab == _Tab.recommended) {
      final hubs = _hubs;
      if (hubs == null) return [message(const PlexSpinner())];
      if (hubs.isEmpty) return [message(Text(l10n.noItemsFound, style: text))];
      return [
        SliverList.builder(
          itemCount: hubs.length,
          itemBuilder: (context, i) => _HubRow(
            key: _hubKeys[i],
            title: hubs[i].title,
            items: hubs[i].items,
            imageUrl: (item, width) => _imageUrl(item, width, 2 / 3),
            onOpen: _open,
            onMenu: _menu,
            onFocusItem: _followFocus,
            onUp: () => i == 0
                ? _tabNodes[_tab]!.requestFocus()
                : _hubKeys[i - 1].currentState?.focusRemembered(),
            onDown: () {
              if (i < hubs.length - 1) {
                _hubKeys[i + 1].currentState?.focusRemembered();
              }
            },
            onBack: () {
              if (_scroll.hasClients) _scroll.jumpTo(0);
              _tabNodes[_tab]!.requestFocus();
            },
          ),
        ),
      ];
    }

    if (_tab == _Tab.collections) return [_buildGrid(_collections)];

    final vm = _vm;
    if (vm == null || vm.state == LibraryBrowseState.loading) {
      return [message(const PlexSpinner())];
    }
    if (vm.state == LibraryBrowseState.error) {
      return [
        message(
          Text(
            vm.isNetworkError
                ? l10n.unableToConnectToServer
                : l10n.noItemsFound,
            style: text,
          ),
        ),
      ];
    }
    if (vm.items.isEmpty) {
      return [message(Text(l10n.noItemsFound, style: text))];
    }
    if (_type.isTracks) return [_buildTracks(vm)];
    return [
      _buildGrid(vm.items),
      if (vm.loadingMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: PlexStyle.s(20)),
            child: const Center(child: PlexSpinner()),
          ),
        ),
    ];
  }

  Widget _buildGrid(List<AggregatedItem> items) {
    final columns = _columns;
    final aspectRatio = _aspectRatio;
    // Plex's six posters span 805 of its 960; a four-wide landscape grid
    // fills the same width.
    final gridWidth = _posterWidth * 6 + _gridGap * 5;
    final available = _contentWidth - PlexStyle.contentInset;
    final width = available.clamp(0.0, gridWidth);
    final cardWidth = (width - _gridGap * (columns - 1)) / columns;
    final cellHeight = PlexPosterCard.cellHeight(cardWidth, aspectRatio);
    // Posters keep Plex's 245 row to row; square and wide artwork, which Plex
    // shows shorter, keep its gap instead.
    final rowGap = aspectRatio < 1
        ? (_rowStride - cellHeight).clamp(0.0, double.infinity)
        : PlexStyle.s(20);
    _stride = cellHeight + rowGap;
    return SliverPadding(
      // The rest of the width (the alphabet's column) stays empty.
      padding: EdgeInsets.only(
        left: PlexStyle.contentInset,
        right: (available - width).clamp(0.0, double.infinity),
      ),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: _gridGap,
          mainAxisSpacing: rowGap,
          mainAxisExtent: cellHeight,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          final (title, subtitle) = _captions(item);
          return PlexPosterCard(
            key: ValueKey(item.id),
            item: item,
            imageUrl: _imageUrl(item, cardWidth, aspectRatio),
            width: cardWidth,
            aspectRatio: aspectRatio,
            title: title,
            subtitle: subtitle,
            focusNode: _gridNode(index),
            onTap: () => _open(item),
            onLongPress: () => _menu(item),
            onFocusChange: (focused) {
              if (focused) _onCardFocus(index, item);
            },
            onKeyEvent: (_, event) => _onCardKey(index, event),
          );
        }, childCount: items.length),
      ),
    );
  }

  Widget _buildTracks(LibraryBrowseViewModel vm) {
    final items = vm.items;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(PlexStyle.contentInset, 0, _barRight, 0),
      sliver: SliverFixedExtentList.builder(
        itemExtent: PlexStyle.s(48),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final track = items[index];
          return TrackTile(
            key: ValueKey('plex-track-${track.id}'),
            track: track,
            focusNode: _gridNode(index),
            onFocused: () {
              _lastGridIndex = index;
              if (vm.hasMore && !vm.loadingMore && index >= items.length - 10) {
                unawaited(vm.loadMore());
              }
            },
            onArrowUp: index == 0 ? _focusAboveGrid : null,
            index: index + 1,
            totalCount: items.length,
            currentIndex: index,
            reorderable: false,
            reorderIndex: index,
            onTap: () => _playTracksFrom(index),
            showAlbum: true,
          );
        },
      ),
    );
  }

  Widget _buildLetters() {
    final order = _letterOrder;
    final cell = PlexStyle.s(15.4);
    return Positioned(
      right: PlexStyle.s(50),
      top: PlexStyle.s(98),
      width: PlexStyle.s(20),
      height: cell * order.length,
      child: ValueListenableBuilder<String?>(
        valueListenable: _activeLetter,
        builder: (context, active, _) => Column(
          children: [
            for (var i = 0; i < order.length; i++)
              _PlexLetter(
                letter: order[i],
                height: cell,
                active: order[i] == active,
                focusNode: _letterNodes[_letters.indexOf(order[i])],
                onKey: (event) {
                  if (!event.isActionable) return false;
                  final key = event.logicalKey;
                  if (key.isUpKey) {
                    if (i > 0) {
                      _letterNodes[_letters.indexOf(order[i - 1])]
                          .requestFocus();
                    }
                    return true;
                  }
                  if (key.isDownKey) {
                    if (i < order.length - 1) {
                      _letterNodes[_letters.indexOf(order[i + 1])]
                          .requestFocus();
                    }
                    return true;
                  }
                  if (key.isLeftKey || key.isBackKey) {
                    _focusCard(_lastGridIndex.clamp(0, _gridItems.length - 1));
                    return true;
                  }
                  return key.isRightKey;
                },
                onTap: () => unawaited(_jumpToLetter(order[i])),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tab at the top of the page: white when active, with Plex's gold line
/// under it, grey otherwise. Focus lights it in a soft pill.
class _PlexTab extends StatefulWidget {
  final String label;
  final bool active;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final bool Function(KeyEvent event) onKey;

  const _PlexTab({
    required this.label,
    required this.active,
    required this.focusNode,
    required this.onSelect,
    required this.onKey,
  });

  @override
  State<_PlexTab> createState() => _PlexTabState();
}

class _PlexTabState extends State<_PlexTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = _focused || widget.active;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      // OK switches, not focus landing: focus passing over a tab (the rail
      // handing over, say) would otherwise swap the page under the user.
      onKeyEvent: (_, event) {
        if (isActivateKey(event)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return widget.onKey(event)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        // The gold line runs the label's width, as in Plex.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: PlexMotion.focus,
                padding: EdgeInsets.symmetric(
                  horizontal: PlexStyle.s(9),
                  vertical: PlexStyle.s(4),
                ),
                decoration: BoxDecoration(
                  color: _focused ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(PlexStyle.s(3)),
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: _focused
                        ? Colors.black
                        : Colors.white.withValues(alpha: lit ? 0.95 : 0.6),
                    fontSize: PlexStyle.s(12.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(height: PlexStyle.s(3)),
              Container(
                height: PlexStyle.s(1.75),
                color: widget.active && !_focused
                    ? PlexStyle.accent
                    : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button in the filter row: Plex's flat grey block, white with black
/// content while focused.
class _PlexBarButton extends StatefulWidget {
  final FocusNode focusNode;
  final bool Function(KeyEvent event) onKey;
  final VoidCallback onTap;
  final Widget child;
  final bool square;

  const _PlexBarButton({
    required this.focusNode,
    required this.onKey,
    required this.onTap,
    required this.child,
    this.square = false,
  });

  @override
  State<_PlexBarButton> createState() => _PlexBarButtonState();
}

class _PlexBarButtonState extends State<_PlexBarButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final height = PlexStyle.s(32);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: (_, event) {
        if (isActivateKey(event)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return widget.onKey(event)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PlexMotion.focus,
          height: height,
          width: widget.square ? height : null,
          padding: widget.square
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(horizontal: PlexStyle.s(16)),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(PlexStyle.s(2)),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: _focused ? Colors.black : Colors.white),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: _focused ? Colors.black : Colors.white),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarLabel extends StatelessWidget {
  final String text;

  const _BarLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, style: TextStyle(fontSize: PlexStyle.s(12.5)));
}

class _BarIcon extends StatelessWidget {
  final IconData icon;
  final bool fill;

  const _BarIcon(this.icon, {this.fill = false});

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: PlexStyle.s(19), fill: fill ? 1 : 0);
}

/// Plex's small solid triangle after a dropdown's label.
class _Caret extends StatelessWidget {
  const _Caret();

  @override
  Widget build(BuildContext context) =>
      Icon(Symbols.arrow_drop_down, size: PlexStyle.s(22), fill: 1);
}

/// One letter of the alphabet down the right edge.
class _PlexLetter extends StatefulWidget {
  final String letter;
  final double height;
  final bool active;
  final FocusNode focusNode;
  final bool Function(KeyEvent event) onKey;
  final VoidCallback onTap;

  const _PlexLetter({
    required this.letter,
    required this.height,
    required this.active,
    required this.focusNode,
    required this.onKey,
    required this.onTap,
  });

  @override
  State<_PlexLetter> createState() => _PlexLetterState();
}

class _PlexLetterState extends State<_PlexLetter> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (_focused) {
      color = Colors.black;
    } else if (widget.active) {
      color = PlexStyle.accent;
    } else {
      color = Colors.white.withValues(alpha: 0.6);
    }
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: (_, event) {
        if (isActivateKey(event)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return widget.onKey(event)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(PlexStyle.s(2)),
          ),
          child: Text(
            widget.letter,
            style: TextStyle(
              color: color,
              fontSize: PlexStyle.s(11),
              fontWeight: widget.active || _focused
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A dropdown's list, opened under its button: the current choice ticked
/// (or, for the sort, marked with its direction) and focused first.
class _PlexMenu extends StatefulWidget {
  final Rect anchor;
  final List<String> labels;
  final int selected;
  final IconData selectedIcon;

  const _PlexMenu({
    required this.anchor,
    required this.labels,
    required this.selected,
    required this.selectedIcon,
  });

  @override
  State<_PlexMenu> createState() => _PlexMenuState();
}

class _PlexMenuState extends State<_PlexMenu> {
  late final _nodes = List.generate(
    widget.labels.length,
    (i) => FocusNode(debugLabel: 'plex-menu-$i'),
  );
  int _focused = -1;

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rowHeight = PlexStyle.s(30);
    final anchor = widget.anchor;
    final screen = MediaQuery.sizeOf(context);
    final height = rowHeight * widget.labels.length + PlexStyle.s(12);
    final below = anchor.bottom + PlexStyle.s(4);
    final top = below + height > screen.height - PlexStyle.s(12)
        ? (screen.height - PlexStyle.s(12) - height).clamp(0.0, below)
        : below;
    final start = widget.selected < 0 ? 0 : widget.selected;
    return Stack(
      children: [
        Positioned(
          left: anchor.left,
          top: top,
          child: Material(
            color: const Color(0xFF282A2D),
            borderRadius: BorderRadius.circular(PlexStyle.s(3)),
            elevation: 8,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: PlexStyle.s(6)),
              child: IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: anchor.width.clamp(PlexStyle.s(140), 600.0),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.labels.length; i++)
                        Focus(
                          focusNode: _nodes[i],
                          autofocus: i == start,
                          onFocusChange: (focused) {
                            if (focused) setState(() => _focused = i);
                          },
                          onKeyEvent: (_, event) {
                            if (isActivateKey(event)) {
                              Navigator.of(context).pop(i);
                              return KeyEventResult.handled;
                            }
                            if (!event.isActionable) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key.isUpKey) {
                              if (i > 0) _nodes[i - 1].requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key.isDownKey) {
                              if (i < _nodes.length - 1) {
                                _nodes[i + 1].requestFocus();
                              }
                              return KeyEventResult.handled;
                            }
                            // Sideways closes nothing and goes nowhere.
                            return key.isLeftKey || key.isRightKey
                                ? KeyEventResult.handled
                                : KeyEventResult.ignored;
                          },
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(i),
                            child: _menuRow(i, rowHeight),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuRow(int i, double height) {
    final focused = _focused == i;
    final color = focused ? Colors.black : Colors.white;
    return Container(
      height: height,
      color: focused ? Colors.white : Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: PlexStyle.s(14)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.labels[i],
              maxLines: 1,
              style: TextStyle(
                color: color.withValues(alpha: focused ? 1 : 0.9),
                fontSize: PlexStyle.s(12.5),
              ),
            ),
          ),
          SizedBox(width: PlexStyle.s(16)),
          SizedBox(
            width: PlexStyle.s(16),
            child: i == widget.selected
                ? Icon(
                    widget.selectedIcon,
                    size: PlexStyle.s(15),
                    color: focused ? Colors.black : PlexStyle.accent,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// A Recommended row: its title and bare posters, as on home. Focus stays
/// pinned to the row's left edge as it moves along.
class _HubRow extends StatefulWidget {
  final String title;
  final List<AggregatedItem> items;
  final String? Function(AggregatedItem item, double width) imageUrl;
  final ValueChanged<AggregatedItem> onOpen;
  final ValueChanged<AggregatedItem> onMenu;
  final ValueChanged<AggregatedItem> onFocusItem;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onBack;

  const _HubRow({
    super.key,
    required this.title,
    required this.items,
    required this.imageUrl,
    required this.onOpen,
    required this.onMenu,
    required this.onFocusItem,
    required this.onUp,
    required this.onDown,
    required this.onBack,
  });

  @override
  State<_HubRow> createState() => _HubRowState();
}

class _HubRowState extends State<_HubRow> {
  final _scroll = ScrollController();
  late final _nodes = List.generate(
    widget.items.length,
    (i) => FocusNode(debugLabel: 'plex-hub-${widget.title}-$i'),
  );
  int _remembered = 0;

  static final _width = PlexStyle.posterWidth;
  static final _gap = PlexStyle.posterGap;

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void focusAt(int index) {
    if (_nodes.isEmpty) return;
    _nodes[index.clamp(0, _nodes.length - 1)].requestFocus();
  }

  void focusRemembered() => focusAt(_remembered);

  void _onFocus(int index) {
    _remembered = index;
    widget.onFocusItem(widget.items[index]);
    final row = context;
    unawaited(
      Scrollable.ensureVisible(
        row,
        alignment: 0.35,
        duration: PlexMotion.move,
        curve: PlexMotion.curve,
      ),
    );
    if (_scroll.hasClients) {
      final target = (index * (_width + _gap)).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      unawaited(
        _scroll.animateTo(
          target,
          duration: PlexMotion.move,
          curve: PlexMotion.curve,
        ),
      );
    }
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isLeftKey) {
      if (index == 0) {
        plexFocusRailFromEdge();
      } else {
        _nodes[index - 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index < _nodes.length - 1) _nodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isUpKey) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      widget.onDown();
      return KeyEventResult.handled;
    }
    if (key.isBackKey && event is KeyDownEvent) {
      widget.onBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final height = _width * 1.5;
    final grow = height * (PlexStyle.focusedPosterScale - 1) / 2;
    return Padding(
      padding: EdgeInsets.only(top: PlexStyle.s(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: PlexStyle.contentInset),
            child: Text(widget.title, style: PlexStyle.rowTitleStyle),
          ),
          SizedBox(
            height: height + grow * 2 + PlexStyle.s(8),
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: PlexStyle.contentInset),
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => SizedBox(width: _gap),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return Center(
                  child: PlexPosterCard(
                    item: item,
                    imageUrl: widget.imageUrl(item, _width),
                    width: _width,
                    aspectRatio: 2 / 3,
                    title: item.type == 'Episode'
                        ? item.seriesName ?? item.name
                        : item.name,
                    showCaptions: false,
                    focusNode: _nodes[index],
                    onTap: () => widget.onOpen(item),
                    onLongPress: () => widget.onMenu(item),
                    onFocusChange: (focused) {
                      if (focused) _onFocus(index);
                    },
                    onKeyEvent: (_, event) => _onKey(index, event),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
