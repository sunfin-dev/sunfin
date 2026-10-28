import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/viewmodels/item_detail_view_model.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/detail_section_layout.dart';
import '../../preference/user_preferences.dart';
import '../../util/detail_trailer.dart';
import '../../util/focus/dpad_keys.dart';
import '../screens/detail/detail_buttons.dart';
import '../screens/detail/item_detail_screen.dart';
import '../screens/detail/nouveau/discovery/nouveau_discovery_section.dart';
import '../screens/detail/nouveau/extras/nouveau_extras_section.dart';
import '../screens/detail/nouveau/people/nouveau_people_section.dart';
import '../widgets/navigation_layout.dart';
import 'plex_backdrop.dart';
import 'plex_clock.dart';
import 'plex_detail_parts.dart';
import 'plex_home_header.dart';
import 'plex_rating_line.dart';
import 'plex_style.dart';

/// Plex's movie page (references 05 to 07; the user's picks from
/// https://claude.ai/artifact/TnMTJm3n8J2xrCyoWmfYcz, 2026-10-28):
///
/// - the title, year, runtime and age rating, genres, the rating line, the
///   summary and "Directed by";
/// - Play, Favorite (Plex's Watchlist spot), Watched, Trailer (Plex's Share
///   spot, when there is one) and More, which lists every other button the
///   user arranged for the details screen;
/// - the quality, audio and subtitle chips at the right;
/// - the page's sections below, in the user's order: Cast & Crew first in
///   Plex, then extras and More Like This in Plex's "Related Movies" spot.
///
/// Plex's Ratings & Reviews and Share have nothing behind them in Jellyfin.
class PlexMoviePage extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final ValueListenable<String?> backdropUrl;
  final String? selectedMediaSourceId;
  final ValueChanged<String?> onSelectedMediaSourceChanged;
  final bool autoPlay;

  /// The node the rail hands focus back to; it passes it on to wherever the
  /// user last was on this page.
  final FocusNode? initialFocusNode;

  const PlexMoviePage({
    super.key,
    required this.viewModel,
    required this.prefs,
    required this.backdropUrl,
    required this.selectedMediaSourceId,
    required this.onSelectedMediaSourceChanged,
    this.autoPlay = false,
    this.initialFocusNode,
  });

  /// Movies, and the videos that play like one.
  static bool handles(AggregatedItem? item) =>
      item?.type == 'Movie' ||
      item?.type == 'Video' ||
      item?.type == 'MusicVideo';

  @override
  State<PlexMoviePage> createState() => _PlexMoviePageState();
}

enum _Button { play, favorite, watched, trailer, more }

// Layout, in Plex's 960-wide units (reference 05). The buttons sit at
// _buttonsTop, or lower when a long summary and "Directed by" need the room.
final _buttonsTop = PlexStyle.s(267);
final _headerGap = PlexStyle.s(20);
final _buttonSize = PlexStyle.s(32);
final _buttonGap = PlexStyle.s(12);
final _chipsGap = PlexStyle.s(4);
final _foldBottom = PlexStyle.s(11);
final _rightInset = PlexStyle.s(40);

const _move = Duration(milliseconds: 180);

class _PlexMoviePageState extends State<PlexMoviePage> {
  final _actionsKey = GlobalKey<DetailActionButtonsState>();
  final _scroll = ScrollController();

  final _peopleKey = GlobalKey<NouveauPeopleSectionState>();
  final _extrasKey = GlobalKey<NouveauExtrasSectionState>();
  final _discoveryKey = GlobalKey<NouveauDiscoverySectionState>();

  late final FocusNode _entryNode =
      widget.initialFocusNode ?? FocusNode(debugLabel: 'plexMovieEntry');
  final _buttonNodes = {
    for (final b in _Button.values) b: FocusNode(debugLabel: 'plexMovie $b'),
  };

  _Button _lastButton = _Button.play;

  /// A page builds again on every view-model update while it opens (ratings,
  /// extras, similar titles), so the top and each section are handed back
  /// unchanged unless what they show changed.
  final _memo = PlexMemo();
  int _prefsRevision = 0;

  ItemDetailViewModel get _vm => widget.viewModel;
  AggregatedItem? get _item => _vm.item;
  double get _inset => PlexStyle.contentInset;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChanged);
    widget.prefs.addListener(_onPrefsChanged);
    NavigationLayout.focusDetailsPlayButtonNotifier.value = _entryNode;
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    widget.prefs.removeListener(_onPrefsChanged);
    if (NavigationLayout.focusDetailsPlayButtonNotifier.value == _entryNode) {
      NavigationLayout.focusDetailsPlayButtonNotifier.value = null;
    }
    if (widget.initialFocusNode == null) _entryNode.dispose();
    for (final node in _buttonNodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onPrefsChanged() {
    if (mounted) setState(() => _prefsRevision++);
  }

  bool get _hasTrailer {
    final item = _item;
    return item != null && hasTrailer(item, _vm.features);
  }

  List<_Button> get _buttons => [
    _Button.play,
    _Button.favorite,
    _Button.watched,
    if (_hasTrailer) _Button.trailer,
    _Button.more,
  ];

  static bool _inProgress(AggregatedItem item) =>
      !item.isPlayed && (item.playbackPositionTicks ?? 0) > 0;

  // --- Focus --------------------------------------------------------------

  void _restoreFocus() {
    final button = _buttons.contains(_lastButton) ? _lastButton : _Button.play;
    _buttonNodes[button]!.requestFocus();
  }

  void _revealTop() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0, duration: _move, curve: Curves.easeOutCubic);
    }
  }

  KeyEventResult _onButtonKey(_Button button, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final buttons = _buttons;
    final index = buttons.indexOf(button);
    if (isActivateKey(event)) {
      if (event is KeyDownEvent) _press(button);
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      if (index > 0) {
        _buttonNodes[buttons[index - 1]]!.requestFocus();
      } else {
        NavigationLayout.focusNavbar();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (index < buttons.length - 1) {
        _buttonNodes[buttons[index + 1]]!.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      _focusSection(0);
      return KeyEventResult.handled;
    }
    if (key.isUpKey) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  // --- Actions ------------------------------------------------------------

  void _press(_Button button) {
    final item = _item;
    final actions = _actionsKey.currentState;
    if (item == null) return;
    switch (button) {
      case _Button.play:
        if (actions == null) return;
        unawaited(
          actions
              .playItem(context, item, resume: _inProgress(item))
              .catchError((Object e) => debugPrint('[PlexMoviePage] play: $e')),
        );
      case _Button.favorite:
        unawaited(_vm.toggleFavorite());
      case _Button.watched:
        unawaited(_vm.togglePlayed());
      case _Button.trailer:
        if (actions != null) unawaited(actions.playTrailer(context));
      case _Button.more:
        if (actions == null) return;
        unawaited(
          actions.showMoreMenu(
            context,
            except: const {
              DetailButton.favorite,
              DetailButton.watched,
              DetailButton.trailer,
            },
          ),
        );
    }
  }

  // --- Sections -----------------------------------------------------------

  List<({GlobalKey key, Widget child})> _sections(AggregatedItem item) {
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
      // It listens to the view model itself, so only a new title or setting
      // builds it again.
      if (NouveauDiscoverySection.shouldInclude(_vm, visibility))
        (
          key: _discoveryKey,
          rank: rank[DetailSection.moreLikeThis]!,
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

  bool _focusSection(int index) {
    for (var i = index; i < _sectionKeys.length; i++) {
      if (_focusSectionAt(i)) return true;
    }
    return false;
  }

  bool _sectionUp(GlobalKey from) {
    final index = _sectionKeys.indexOf(from);
    for (var i = index - 1; i >= 0; i--) {
      if (_focusSectionAt(i)) return true;
    }
    _revealTop();
    _restoreFocus();
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
    _revealSection(key);
    return true;
  }

  bool _sectionDown(GlobalKey from) {
    _focusSection(_sectionKeys.indexOf(from) + 1);
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
    final sections = _sections(item);
    _sectionKeys = [for (final s in sections) s.key];
    final directors = _vm.directors;

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
                _memo(
                  #fold,
                  [item, _vm.ratings, directors, _hasTrailer, _prefsRevision],
                  () => _buildFold(item, directors),
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
        // Only there for what it does: playback (prerolls, resume, the
        // external player), the trailer and the menu behind More.
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
                autoPlay: widget.autoPlay,
                nouveauStyle: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFold(
    AggregatedItem item,
    List<Map<String, dynamic>> directors,
  ) {
    final l10n = AppLocalizations.of(context);
    final names = [
      for (final person in directors)
        if ((person['Name'] as String?)?.trim() case final name?
            when name.isNotEmpty)
          name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlexHomeHeader(
          item: item,
          leftInset: _inset,
          showCast: false,
          height: _buttonsTop - _headerGap,
          grow: true,
          ratingLine: PlexRatingLine.of(
            item: item,
            extraRatings: _vm.ratings,
            prefs: widget.prefs,
          ),
          footer: names.isEmpty
              ? null
              : l10n.plexDirectedBy(names.take(2).join(', ')),
        ),
        SizedBox(height: _headerGap),
        Padding(
          padding: EdgeInsets.only(left: _inset),
          child: _buildButtons(item),
        ),
        SizedBox(height: _chipsGap),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: _rightInset),
            child: PlexMediaChips(item: item),
          ),
        ),
        SizedBox(height: _foldBottom),
      ],
    );
  }

  Widget _buildButtons(AggregatedItem item) {
    final l10n = AppLocalizations.of(context);
    final playLabel = _inProgress(item) ? l10n.resume : l10n.play;
    final buttons = _buttons;
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) SizedBox(width: _buttonGap),
          _buildButton(buttons[i], item, playLabel),
        ],
      ],
    );
  }

  Widget _buildButton(_Button button, AggregatedItem item, String playLabel) {
    final node = _buttonNodes[button]!;
    return Focus(
      focusNode: node,
      onFocusChange: (f) {
        if (!f) return;
        _lastButton = button;
        _revealTop();
      },
      onKeyEvent: (_, event) => _onButtonKey(button, event),
      child: GestureDetector(
        onTap: () => _press(button),
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => switch (button) {
            _Button.play => PlexPlayButton(
              label: playLabel,
              focused: node.hasFocus,
              size: _buttonSize,
            ),
            _ => PlexRoundButton(
              icon: switch (button) {
                _Button.favorite => Symbols.favorite,
                _Button.watched => Symbols.check_circle,
                _Button.trailer => Symbols.smart_display,
                _ => Symbols.more_horiz,
              },
              filled:
                  (button == _Button.favorite && item.isFavorite) ||
                  (button == _Button.watched && item.isPlayed),
              focused: node.hasFocus,
              size: _buttonSize,
            ),
          },
        ),
      ),
    );
  }
}
