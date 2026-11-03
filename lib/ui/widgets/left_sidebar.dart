import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../auth/repositories/user_repository.dart';
import '../screens/admin/admin_access.dart';
import '../../data/models/aggregated_library.dart';
import '../../data/repositories/multi_server_repository.dart';
import '../../data/repositories/user_views_repository.dart';
import '../../data/services/achievements_service.dart';
import '../../data/services/library_scope_service.dart';
import '../../data/services/plugin_sync_service.dart';
import '../../preference/preference_constants.dart';
import '../../preference/seerr_preferences.dart';
import '../../preference/user_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../util/clock_format.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/game_library.dart';
import '../../util/live_tv_library.dart';
import '../../util/overlay_color_palette.dart';
import '../../util/platform_detection.dart';
import '../navigation/destinations.dart';
import '../navigation/home_refresh_bus.dart';
import '../navigation/route_lifecycle_observer.dart';
import '../sunfin/sunfin_backdrop_tint.dart';
import '../sunfin/sunfin_icons.dart';
import '../sunfin/sunfin_library_page.dart';
import '../sunfin/sunfin_style.dart';
import 'navigation_layout.dart';
import 'settings/settings_panel.dart';
import '../screens/downloads/downloads_panel.dart';
import 'downloads_nav_slot.dart';
import 'friends_nav_slot.dart';
import '../screens/syncplay/syncplay_screen.dart';
import '../screens/settings/settings_side_panel.dart';
import 'seerr_icons.dart';
import 'server_messages_dialog.dart';
import 'server_messages_nav_slot.dart';
import 'unread_badge.dart';
import 'shuffle_overlay.dart';
import 'user_menu_dialog.dart';

import 'package:playback_core/playback_core.dart';
import '../../data/models/aggregated_item.dart';
import '../../data/services/media_server_client_factory.dart';
import '../navigation/app_router.dart';
import 'offline_aware_image.dart';
import 'paced_network_image.dart';
import 'adaptive/sf_symbol.dart';

const _kExpandedWidthDesktop = 240.0;
const _kExpandedWidthMobile = 260.0;
const _kExpandDuration = SunfinMotion.move;
const _kExpandedWidthTV = 280.0;
const _kCollapsedWidthTV = 72.0;
const _kExpandedBackdropWidthTV = _kExpandedWidthTV - 16.0;
const _kBackdropEdgeBlendWidthTV =
    _kExpandedWidthTV - _kExpandedBackdropWidthTV;

class LeftSidebar extends StatefulWidget {
  final String? activeRoute;
  final FocusNode? contentFocusNode;
  final bool showBackButton;

  /// Notifier updated when the sidebar's focus state changes.
  /// Use this instead of walking the element tree to determine if the
  /// current focus is within the sidebar; it's resilient during teardown.
  static final ValueNotifier<bool> isFocusedNotifier = ValueNotifier<bool>(false);

  /// Sunfin mode: how much of the screen's left edge the rail takes, which is
  /// where the content starts. It jumps to the target of an expand or
  /// collapse; the rail and content get there over [expandDuration] on
  /// [expandCurve]. Zero outside Sunfin mode. Follows the sidebar of the route
  /// on screen.
  static final ValueNotifier<double> railWidthNotifier = ValueNotifier<double>(
    0,
  );

  static const expandDuration = _kExpandDuration;
  static const expandCurve = SunfinMotion.curve;

  /// Sunfin mode: how wide the open rail is. It fits the longest label the
  /// rail shows (a long library name widens it), so the layout reads it here
  /// to slide the content by the same amount.
  static final ValueNotifier<double> sunfinExpandedWidthNotifier =
      ValueNotifier<double>(SunfinStyle.railExpandedWidth);

  /// Set by [NavigationLayout] so its content can move with this rail.
  final ValueNotifier<bool>? expandedNotifier;

  const LeftSidebar({
    super.key,
    this.activeRoute,
    this.contentFocusNode,
    this.showBackButton = false,
    this.expandedNotifier,
  });

  @override
  State<LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<LeftSidebar> with RouteAware {
  final _userRepo = GetIt.instance<UserRepository>();
  final _prefs = GetIt.instance<UserPreferences>();
  final _viewsRepo = GetIt.instance<UserViewsRepository>();
  final _sidebarFocus = FocusScopeNode(debugLabel: 'LeftSidebar');
  final _homeFocusNode = FocusNode(debugLabel: 'LeftSidebarHome');
  final _searchFocusNode = FocusNode(debugLabel: 'LeftSidebarSearch');
  // Sunfin mode lists every library as its own row; keyed by library id so a
  // row keeps its node (and focus) across library reloads.
  final Map<String, FocusNode> _libraryFocusNodes = {};
  final _settingsFocusNode = FocusNode(debugLabel: 'LeftSidebarSettings');
  final _serverMessagesFocusNode = FocusNode(
    debugLabel: 'LeftSidebarServerMessages',
  );
  final _friendsFocusNode = FocusNode(debugLabel: 'LeftSidebarFriends');
  final _profileFocusNode = FocusNode(debugLabel: 'LeftSidebarProfile');
  final _musicCardFocusNode = FocusNode(debugLabel: 'SidebarMusicCard');
  late final VoidCallback _focusNavbarCallback;
  late final VoidCallback _focusAvatarCallback;
  VoidCallback? _previousFocusNavbarCallback;
  VoidCallback? _previousFocusAvatarCallback;
  final _scrollController = ScrollController();

  List<AggregatedLibrary> _libraries = [];
  bool _isExpanded = false;
  bool _showLabels = false;
  bool _librariesExpanded = false;
  bool _canExpandViaFocus = false;
  bool _skipExpandOnNextFocusFromNavigation = false;
  // Tracked per instance instead of reading the shared isFocusedNotifier,
  // where a stale value from another route's sidebar would break focus-gain
  // detection and leave focus stuck in a collapsed rail.
  bool _sidebarHadFocus = false;
  bool _friendsAvailable = FriendsNavSlot.isAvailable();
  Timer? _clockTimer;
  Timer? _labelTimer;
  Timer? _focusExpandGateTimer;
  Timer? _focusHomeTimer;
  Timer? _librariesReloadDebounce;
  late final ValueNotifier<String> _currentTime;
  StreamSubscription? _userSub;
  String? _userImageUrl;
  FocusNode? _previousFocus;

  bool get _isMobile => PlatformDetection.useMobileUi;

  @override
  void initState() {
    super.initState();
    _currentTime = ValueNotifier<String>('');
    _focusNavbarCallback = () {
      if (!mounted || _homeFocusNode.context == null) return;
      // Expand the rail directly instead of relying on the focus listener,
      // whose expansion can be blocked right after this sidebar mounts.
      if (!_isMobile && !_isExpanded) {
        _expand();
      }
      _activeEntryFocusNode().requestFocus();
    };
    _focusAvatarCallback = () {
      if (!mounted) return;
      if (_profileFocusNode.context != null) {
        _profileFocusNode.requestFocus();
      } else {
        _expand();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_profileFocusNode.context != null) {
            _profileFocusNode.requestFocus();
          } else {
            _homeFocusNode.requestFocus();
          }
        });
      }
    };
    _previousFocusNavbarCallback = NavigationLayout.focusNavbarNotifier.value;
    _previousFocusAvatarCallback =
        NavigationLayout.focusNavbarAvatarNotifier.value;
    NavigationLayout.focusNavbarNotifier.value = _focusNavbarCallback;
    NavigationLayout.focusNavbarAvatarNotifier.value = _focusAvatarCallback;
    NavigationLayout.chromeFocusRoots.add(_sidebarFocus);
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateClock(),
    );
    _loadUserImage();
    _userSub = _userRepo.currentUserStream.listen((_) => _loadUserImage());
    _prefs.addListener(_onPrefsChanged);
    _viewsRepo.addListener(_onUserViewsChanged);
    GetIt.instance<PluginSyncService>().addListener(_onPrefsChanged);
    if (GetIt.instance.isRegistered<AchievementsService>()) {
      GetIt.instance<AchievementsService>().addListener(_onAchievementsChanged);
    }
    _lastMultiServerLibraries = _prefs.get(
      UserPreferences.enableMultiServerLibraries,
    );
    _loadLibraries();
    FocusManager.instance.addListener(_trackPreviousFocus);
    if (PlatformDetection.isTV || (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      _armTvFocusGate();
      _sidebarFocus.addListener(_onSidebarFocusNodeChanged);
    }
    if (PlatformDetection.isTV) {
      _profileFocusNode.addListener(() {
        if (mounted) setState(() {});
      });
    }
    // Not during this build: the layout listens and would rebuild mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishRailState());
  }

  ModalRoute<dynamic>? _observedRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) {
      routeLifecycleObserver.unsubscribe(this);
    }
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Our route is current again. An out of order route teardown can leave
    // the focus bridge pointing at a torn-down chrome instance, so re-assert
    // that it targets this live one.
    NavigationLayout.focusNavbarNotifier.value = _focusNavbarCallback;
    NavigationLayout.focusNavbarAvatarNotifier.value = _focusAvatarCallback;
    _publishRailState();
  }

  @override
  void dispose() {
    if (_observedRoute != null) {
      routeLifecycleObserver.unsubscribe(this);
      _observedRoute = null;
    }
    if (identical(
      NavigationLayout.focusNavbarNotifier.value,
      _focusNavbarCallback,
    )) {
      NavigationLayout.focusNavbarNotifier.value = _previousFocusNavbarCallback;
    }
    if (identical(
      NavigationLayout.focusNavbarAvatarNotifier.value,
      _focusAvatarCallback,
    )) {
      NavigationLayout.focusNavbarAvatarNotifier.value =
          _previousFocusAvatarCallback;
    }
    NavigationLayout.chromeFocusRoots.remove(_sidebarFocus);
    FocusManager.instance.removeListener(_trackPreviousFocus);
    if (PlatformDetection.isTV || (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      _sidebarFocus.removeListener(_onSidebarFocusNodeChanged);
    }
    _clockTimer?.cancel();
    _labelTimer?.cancel();
    _focusExpandGateTimer?.cancel();
    _focusHomeTimer?.cancel();
    _librariesReloadDebounce?.cancel();
    _homeFocusNode.dispose();
    _searchFocusNode.dispose();
    for (final node in _libraryFocusNodes.values) {
      node.dispose();
    }
    _settingsFocusNode.dispose();
    _serverMessagesFocusNode.dispose();
    _friendsFocusNode.dispose();
    _profileFocusNode.dispose();
    _musicCardFocusNode.dispose();
    _sidebarFocus.dispose();
    _scrollController.dispose();
    _userSub?.cancel();
    try {
      _viewsRepo.removeListener(_onUserViewsChanged);
    } catch (_) {}
    try {
      GetIt.instance<PluginSyncService>().removeListener(_onPrefsChanged);
    } catch (_) {}
    try {
      GetIt.instance<AchievementsService>().removeListener(
        _onAchievementsChanged,
      );
    } catch (_) {}
    _prefs.removeListener(_onPrefsChanged);
    _currentTime.dispose();
    // Only clear the shared flag if this instance held focus, so a torn-down
    // route's sidebar can't wipe the state of the one the user is on.
    if (_sidebarHadFocus) {
      LeftSidebar.isFocusedNotifier.value = false;
    }
    super.dispose();
  }

  bool? _lastMultiServerLibraries;

  void _onPrefsChanged() {
    if (!mounted) return;
    _updateClock();
    // Sunfin: the list only depends on the server's views, which notify on
    // their own (_onUserViewsChanged), and, with several servers, on the
    // per-server visibility kept here. Any other setting used to cost a
    // server round trip for a list that could not have changed.
    final multiServer = _prefs.get(UserPreferences.enableMultiServerLibraries);
    if (multiServer || multiServer != _lastMultiServerLibraries) {
      _scheduleLibrariesReload();
    }
    _lastMultiServerLibraries = multiServer;
    setState(() {});
    // Sunfin mode can be switched on or off from the settings.
    _publishRailState();
  }

  /// Tells the layout (and screens) how wide the rail now is.
  void _publishRailState() {
    if (!mounted) return;
    widget.expandedNotifier?.value = _isExpanded;
    LeftSidebar.railWidthNotifier.value = !SunfinStyle.enabled
        ? 0
        : _isExpanded
        ? LeftSidebar.sunfinExpandedWidthNotifier.value
        : SunfinStyle.railCollapsedWidth;
  }

  // Row geometry around a label in the open rail: 18 padding each side, the
  // 32 icon slot and a 12 gap (see _SidebarItem); the profile row adds the
  // same 80 around the user's name (margins, avatar, gap).
  static const _sunfinLabelChrome = 80.0;
  static const _sunfinLabelMargin = 0.0;
  String _sunfinWidthKey = '';

  /// Sunfin mode: every label the open rail can show, as _buildContent does.
  List<String> _sunfinRailLabels(AppLocalizations l10n) {
    final kidsMode = _kidsMode;
    final seerrPrefs = GetIt.instance<SeerrPreferences>();
    return [
      l10n.search,
      l10n.home,
      if (!kidsMode && _prefs.get(UserPreferences.showLibrariesInToolbar))
        for (final lib in _navLibraries) lib.name,
      if (_prefs.get(UserPreferences.showShuffleButton)) l10n.shuffle,
      if (_prefs.get(UserPreferences.showGenresButton)) l10n.genres,
      if (_prefs.get(UserPreferences.showFavoritesButton)) l10n.favorites,
      if (_showLiveTvButton) l10n.liveTv,
      if (_prefs.get(UserPreferences.enableFolderView)) l10n.folders,
      if (!kidsMode && _prefs.get(UserPreferences.showSyncPlayButton))
        l10n.syncPlay,
      if (!kidsMode && _prefs.get(UserPreferences.showSeerrButton))
        seerrPrefs.labelOrDefault(l10n.seerr),
      if (DownloadsNavSlot.isOffered()) l10n.savedMedia,
      if (FriendsNavSlot.isOffered() && _friendsAvailable) l10n.friends,
      if (_prefs.get(UserPreferences.showServerMessagesButton))
        l10n.serverMessages,
      l10n.settings,
    ];
  }

  /// Sunfin mode: the open rail's width, measured from its longest label with
  /// the font it is drawn in, never wider than 40% of the screen.
  double _sunfinExpandedWidth() {
    final l10n = AppLocalizations.of(context);
    final labels = _sunfinRailLabels(l10n);
    final userName = _userRepo.currentUser?.name ?? '';
    final key = '${labels.join('\u0000')}\u0001$userName';
    if (key == _sunfinWidthKey) return LeftSidebar.sunfinExpandedWidthNotifier.value;

    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(fontSize: 14, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var widest = measure(userName, FontWeight.w600);
    for (final label in labels) {
      widest = math.max(widest, measure(label, FontWeight.w500));
    }
    // An app started while the display is off sees a zero-width screen, and
    // a cap under the floor would throw.
    final width = (widest + _sunfinLabelChrome + _sunfinLabelMargin).clamp(
      SunfinStyle.railCollapsedWidth,
      math.max<double>(
        SunfinStyle.railCollapsedWidth,
        MediaQuery.sizeOf(context).width * 0.4,
      ),
    );
    _sunfinWidthKey = key;
    // Published after the frame: listeners rebuild the layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LeftSidebar.sunfinExpandedWidthNotifier.value = width;
      _publishRailState();
    });
    return width;
  }

  void _onUserViewsChanged() {
    if (!mounted) return;
    _scheduleLibrariesReload();
  }

  /// The service also notifies on every badge refresh, which the slot redraws
  /// by itself, so the sidebar only rebuilds when the row comes or goes.
  void _onAchievementsChanged() {
    final available = FriendsNavSlot.isAvailable();
    if (!mounted || available == _friendsAvailable) return;
    setState(() => _friendsAvailable = available);
  }

  // Collapses a burst of change notifications, like the settings sync
  // applying a whole profile, into a single library reload.
  void _scheduleLibrariesReload() {
    _librariesReloadDebounce?.cancel();
    _librariesReloadDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadLibraries();
    });
  }

  void _updateClock() {
    final newTime = formatClockTime(
      DateTime.now(),
      use24Hour: _prefs.get(UserPreferences.use24HourClock),
    );
    if (mounted && _currentTime.value != newTime) {
      _currentTime.value = newTime;
    }
  }

  void _loadUserImage() {
    final user = _userRepo.currentUser;
    if (user == null) {
      setState(() => _userImageUrl = null);
      return;
    }
    try {
      final client = GetIt.instance<MediaServerClient>();
      setState(() => _userImageUrl = client.imageApi.getUserImageUrl(user.id));
    } catch (_) {
      setState(() => _userImageUrl = null);
    }
  }

  Future<void> _loadLibraries() async {
    try {
      final useMultiServer = _prefs.get(
        UserPreferences.enableMultiServerLibraries,
      );
      final libs = useMultiServer
          ? await GetIt.instance<MultiServerRepository>()
                .getAggregatedLibraries()
          : await _viewsRepo.getUserViews();

      unawaited(GetIt.instance<GameLibraryRegistry>().refresh());

      final filtered = useMultiServer
          ? await GetIt.instance<LibraryScopeService>().withoutHiddenLibraries(
              libs,
            )
          : libs;

      if (mounted && !_librariesEqual(_libraries, filtered)) {
        setState(() => _libraries = filtered);
      }
    } catch (_) {}
  }

  bool _librariesEqual(List<AggregatedLibrary> a, List<AggregatedLibrary> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // Names too: a library nickname renames without changing any id.
      if (a[i].id != b[i].id || a[i].name != b[i].name) return false;
    }
    return true;
  }

  // Kids Mode sends /live-tv back to home, so the guide button would only be a
  // dead end.
  bool get _showLiveTvButton =>
      !_kidsMode &&
      _prefs.get(UserPreferences.showLiveTvButton) &&
      _libraries.any(isLiveTvLibrary);

  List<AggregatedLibrary> get _navLibraries =>
      librariesForNav(_libraries, _showLiveTvButton, hideLiveTv: _kidsMode);

  bool get _kidsMode => _prefs.get(UserPreferences.kidsModeEnabled);

  Color _overlayColor() {
    return OverlayColorPalette.resolveColor(
      _prefs.get(UserPreferences.navbarColor),
    );
  }

  double _overlayOpacity() {
    return _prefs.get(UserPreferences.navbarOpacity) / 100.0;
  }

  void _expand() {
    if (_isExpanded) return;
    setState(() => _isExpanded = true);
    _publishRailState();
    _labelTimer?.cancel();
    final delay = PlatformDetection.isTV
        ? const Duration(milliseconds: 150)
        : const Duration(milliseconds: 100);
    _labelTimer = Timer(delay, () {
      if (mounted) setState(() => _showLabels = true);
    });
  }

  void _collapse() {
    if (!_isExpanded) return;
    _labelTimer?.cancel();
    setState(() {
      _isExpanded = false;
      _showLabels = false;
      _librariesExpanded = false;
    });
    _publishRailState();
  }

  void _toggle() {
    if (_isExpanded) {
      _collapse();
    } else {
      _expand();
    }
  }

  void _onSidebarFocusNodeChanged() {
    final hasFocus = _sidebarFocus.hasFocus;
    if (hasFocus && !_sidebarHadFocus) {
      if (_skipExpandOnNextFocusFromNavigation) {
        _skipExpandOnNextFocusFromNavigation = false;
        _focusHomeTimer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _exitSidebarToContent();
        });
      } else if (_canExpandViaFocus) {
        _expand();
        _focusHomeTimer?.cancel();
        _focusHomeTimer = Timer(Duration.zero, () {
          if (!mounted) return;
          // Only jump to the home item when nothing specific was focused.
          // A handoff can target a specific item like the avatar, and
          // re-requesting home here would stomp it.
          final primary = FocusManager.instance.primaryFocus;
          final hasSpecificChild = primary != null &&
              !identical(primary, _sidebarFocus) &&
              _isDescendantOf(primary, _sidebarFocus);
          if (!hasSpecificChild) {
            // The reference design lands on the section you are in, not always on Home.
            _activeEntryFocusNode().requestFocus();
          }
        });
      }
    } else if (!hasFocus && _sidebarHadFocus && _canExpandViaFocus) {
      _collapse();
    }
    _sidebarHadFocus = hasFocus;
    LeftSidebar.isFocusedNotifier.value = hasFocus;
  }

  void _markNavigationAwayFromSidebar() {
    if (PlatformDetection.isTV || (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      _skipExpandOnNextFocusFromNavigation = true;
    }
  }

  void _onSidebarFocusChange(bool hasFocus) {
    if (PlatformDetection.isTV || (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      return;
    }
    // On mobile, keep sidebar opening explicit (menu tap) to avoid
    // route-to-route focus restoration repeatedly reopening it.
  }

  void _armTvFocusGate() {
    setState(() => _canExpandViaFocus = false);
    _focusExpandGateTimer?.cancel();
    _focusExpandGateTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _canExpandViaFocus = true);
      // A focus handoff can land while the gate is closed, which leaves a
      // focused item inside a collapsed rail. Heal that now.
      if (_sidebarFocus.hasFocus && !_isExpanded) {
        _expand();
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final primary = FocusManager.instance.primaryFocus;
      final insideMusicCard = primary != null && _isDescendantOf(primary, _musicCardFocusNode);

      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (insideMusicCard) {
          final success = primary.focusInDirection(TraversalDirection.right);
          if (success) {
            return KeyEventResult.handled;
          }
        }
        _collapse();
        _restoreFocusOutsideSidebar();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (insideMusicCard) {
          final success = primary.focusInDirection(TraversalDirection.left);
          if (success) {
            return KeyEventResult.handled;
          }
          if (PlatformDetection.isTV) {
            return KeyEventResult.handled;
          }
        } else {
          if (PlatformDetection.isTV) {
            return KeyEventResult.handled;
          }
        }
      }
      // The top row hands up to the avatar: Search in Sunfin mode, else Home.
      final topNode = SunfinStyle.enabled ? _searchFocusNode : _homeFocusNode;
      if (PlatformDetection.isTV &&
          event.logicalKey == LogicalKeyboardKey.arrowUp &&
          topNode.hasFocus) {
        if (_profileFocusNode.context != null) {
          _profileFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _isDescendantOf(FocusNode? child, FocusNode parent) {
    FocusNode? current = child;
    while (current != null) {
      if (identical(current, parent)) return true;
      current = current.parent;
    }
    return false;
  }

  void _trackPreviousFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || _sidebarFocus.hasFocus) return;
    _previousFocus = primary;
  }

  void _restoreFocusOutsideSidebar() {
    if (NavigationLayout.focusDetailsPlayButton()) return;
    final previous = _previousFocus;
    if (previous != null && _isLaidOutFocusNode(previous)) {
      previous.requestFocus();
      return;
    }
    final fallback = widget.contentFocusNode;
    if (fallback != null && _isLaidOutFocusNode(fallback)) {
      final firstContent = _firstFocusableDescendant(fallback);
      if (firstContent != null) {
        firstContent.requestFocus();
      } else {
        fallback.requestFocus();
      }
      return;
    }
    if (mounted) FocusScope.of(context).nextFocus();
  }

  static bool _isLaidOutFocusNode(FocusNode node) {
    if (!node.canRequestFocus) {
      return false;
    }
    final context = node.context;
    if (context == null) {
      return false;
    }
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize;
  }

  static FocusNode? _firstFocusableDescendant(FocusNode node) {
    for (final child in node.children) {
      if (!child.skipTraversal && _isLaidOutFocusNode(child)) {
        return child;
      }
      final found = _firstFocusableDescendant(child);
      if (found != null) return found;
    }
    return null;
  }

  String _normalizedPath(String path) {
    if (path.isEmpty) return path;
    return (path.endsWith('/') && path.length > 1)
        ? path.substring(0, path.length - 1)
        : path;
  }

  String _currentPath() {
    if (widget.activeRoute != null && widget.activeRoute!.isNotEmpty) {
      return _normalizedPath(widget.activeRoute!);
    }
    try {
      return _normalizedPath(GoRouterState.of(context).uri.path);
    } catch (_) {
      return '';
    }
  }

  /// The page beside the rail is a [SunfinLibraryPage], which the query decides
  /// (a type or favourites view of a library is the upstream grid).
  bool _onPlexLibraryPage() {
    final route = widget.activeRoute;
    if (route != null && route.isNotEmpty) {
      return SunfinLibraryPage.handles(Uri.parse(route));
    }
    try {
      return SunfinLibraryPage.handles(GoRouterState.of(context).uri);
    } catch (_) {
      return false;
    }
  }

  bool _isActive(String route) {
    return _currentPath() == _normalizedPath(route);
  }

  /// Like [_isActive], for routes that carry a query (library routes do).
  bool _isActiveRoute(String route) =>
      _currentPath() == _normalizedPath(Uri.parse(route).path);

  String _libraryRouteFor(AggregatedLibrary lib) => libraryRoute(
    lib.id,
    lib.collectionType,
    lib.name,
    serverId: lib.serverId,
  );

  FocusNode _libraryFocusNode(String id) => _libraryFocusNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'LeftSidebarLibrary-$id'),
  );

  /// The row focus lands on when the rail opens: the section on screen in
  /// Sunfin mode, otherwise Home as upstream does.
  FocusNode _activeEntryFocusNode() {
    if (SunfinStyle.enabled) {
      if (_isActive(Destinations.search)) return _searchFocusNode;
      for (final lib in _navLibraries) {
        final node = _libraryFocusNodes[lib.id];
        if (node != null &&
            node.context != null &&
            _isActiveRoute(_libraryRouteFor(lib))) {
          return node;
        }
      }
    }
    return _homeFocusNode;
  }

  @override
  Widget build(BuildContext context) {
    return _buildDrawerLayout();
  }

  Widget _buildDrawerLayout() {
    if (PlatformDetection.isTV || (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      return _buildTvLayout();
    }
    final expandedWidth = _isMobile
        ? _kExpandedWidthMobile
        : _kExpandedWidthDesktop;
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;
    return Stack(
      children: [
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _collapse,
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
        AnimatedPositioned(
          duration: _kExpandDuration,
          curve: Curves.easeInOut,
          left: _isExpanded ? 0 : -expandedWidth,
          top: 0,
          bottom: 0,
          width: expandedWidth,
          child: FocusScope(
            node: _sidebarFocus,
            onFocusChange: _onSidebarFocusChange,
            onKeyEvent: _onKeyEvent,
            child: AppColorScheme.isGlass
                ? GlassSurface(
                    cornerRadius: 18,
                    reinforced: _isMobile,
                    fallbackColor: Colors.transparent,
                    child: _isMobile
                        ? SafeArea(right: false, child: _buildContent())
                        : _buildContent(),
                  )
                : Container(
              decoration: BoxDecoration(
                gradient: _isMobile
                    ? null
                    : LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          _overlayColor().withValues(alpha: _overlayOpacity()),
                          _overlayColor().withValues(
                            alpha: _overlayOpacity() * 0.75,
                          ),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.7, 1.0],
                      ),
                color: _isMobile
                    ? _overlayColor().withValues(alpha: _overlayOpacity())
                    : null,
                border: isNeon
                    ? Border(
                        right: ThemeRegistry.active.borders.chipBorder.copyWith(
                          color: AppColorScheme.accent,
                          width: 1.2,
                        ),
                      )
                    : null,
                boxShadow: _isExpanded
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 20,
                          offset: const Offset(4, 0),
                        ),
                        if (isNeon)
                          const BoxShadow(
                            color: Color(0x66FF2E92),
                            blurRadius: 12,
                            offset: Offset(2, 0),
                          ),
                        if (isNeon)
                          const BoxShadow(
                            color: Color(0x5500E5FF),
                            blurRadius: 10,
                            offset: Offset(1, 0),
                          ),
                      ]
                    : null,
              ),
              child: _isMobile
                  ? SafeArea(right: false, child: _buildContent())
                  : _buildContent(),
            ),
          ),
        ),
        if (!_isExpanded)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _toggle,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.menu,
                          size: 22,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    if (widget.showBackButton) ...[
                      const SizedBox(width: 6),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.popOrHome(),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Sunfin mode: a solid rail in the theme's surface colour, the same collapsed
  /// and expanded. It no longer floats over the page: navigation_layout.dart
  /// puts the content beside it, so nothing scrolls under the icons.
  Widget _buildPlexRail() {
    final expandedWidth = _sunfinExpandedWidth();
    final surface = AppColorScheme.surface.withValues(alpha: 1);
    // Details pages draw the same Sunfin page as home (user, 2026-10-23), and
    // so do Sunfin library pages (user, 2026-10-27).
    final onPlexPage =
        _isActive(Destinations.home) ||
        _currentPath().startsWith('/item/') ||
        _onPlexLibraryPage();
    return AnimatedContainer(
      duration: _kExpandDuration,
      curve: LeftSidebar.expandCurve,
      width: _isExpanded ? expandedWidth : SunfinStyle.railCollapsedWidth,
      // On home and details pages the rail, open or collapsed, takes the
      // page's tint beside it and fades with it, so there is no seam (user,
      // 2026-10-22). Elsewhere it is the theme's surface.
      // The page's tint runs from one colour at the top of its left edge to
      // another at the bottom (the reference design's four-corner wash), so the rail draws the
      // same blend.
      child: ValueListenableBuilder<(Color, Color)?>(
        valueListenable: SunfinStyle.pageTint,
        builder: (context, tint, child) => TweenAnimationBuilder<SunfinTint>(
          tween: SunfinTintTween(
            end: onPlexPage && tint != null
                ? SunfinTint(
                    topLeft: tint.$1,
                    topRight: tint.$1,
                    bottomLeft: tint.$2,
                    bottomRight: tint.$2,
                  )
                : SunfinTint.solid(surface),
          ),
          duration: SunfinStyle.tintDuration,
          curve: Curves.easeOut,
          builder: (context, value, child) =>
              CustomPaint(
                painter: SunfinTintPainter(value, shadeMiddle: false),
                child: child,
              ),
          child: child,
        ),
        child: ClipRect(
          child: FocusScope(
            node: _sidebarFocus,
            onFocusChange: _onSidebarFocusChange,
            onKeyEvent: _onKeyEvent,
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildTvLayout() {
    if (SunfinStyle.enabled) return _buildPlexRail();
    final backdropColor = _overlayColor().withValues(alpha: _overlayOpacity());
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;
    final desktopHoverRail =
        (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi)) && !PlatformDetection.isTV;
    final railWidth = _isExpanded ? _kExpandedWidthTV : _kCollapsedWidthTV;

    final rail = AnimatedContainer(
      duration: _kExpandDuration,
      curve: Curves.easeInOut,
      width: railWidth,
      child: ClipRect(
        child: FocusScope(
          node: _sidebarFocus,
          onFocusChange: _onSidebarFocusChange,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            children: [
              if (_isExpanded)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: _kExpandedWidthTV,
                    child: Stack(
                      children: [
                        if (AppColorScheme.isGlass)
                          SizedBox(
                            width: _kExpandedBackdropWidthTV,
                            child: const GlassSurface(
                              cornerRadius: 18,
                              fallbackColor: Colors.transparent,
                            ),
                          )
                        else
                          Container(
                            width: _kExpandedBackdropWidthTV,
                            decoration: BoxDecoration(
                              color: backdropColor,
                              border: isNeon
                                  ? Border(
                                      right: ThemeRegistry
                                          .active
                                          .borders
                                          .chipBorder
                                          .copyWith(
                                            color: AppColorScheme.accent,
                                            width: 1.2,
                                          ),
                                    )
                                  : null,
                            ),
                          ),
                        if (!AppColorScheme.isGlass)
                          Positioned(
                            left: _kExpandedBackdropWidthTV,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: _kBackdropEdgeBlendWidthTV,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [backdropColor, Colors.transparent],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: _kExpandDuration,
                  curve: Curves.easeInOut,
                  width: _isExpanded ? _kExpandedBackdropWidthTV : _kCollapsedWidthTV,
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!desktopHoverRail) return rail;

    return MouseRegion(
      onEnter: (_) => _expand(),
      onExit: (_) => _collapse(),
      child: rail,
    );
  }

  /// The downloads row, or nothing while there is nothing saved. The nav
  /// colour is passed in so the caller decides which palette slot it takes.
  Widget _downloadsSidebarItem({
    required Color? navColor,
    required String label,
  }) {
    return DownloadsNavSlot(
      builder: (context) => _SidebarItem(
        key: const ValueKey('sidebar-downloads'),
        icon: Icons.download_for_offline,
        label: label,
        baseColor: navColor,
        showLabel: _showLabels,
        onPressed: () {
          _onNavigate();
          showDownloadsDialog(context);
        },
      ),
    );
  }

  /// The messages row, or nothing when there is nothing to show. The nav colour
  /// is passed in so the caller decides which palette slot it takes.
  Widget _serverMessagesSidebarItem({
    required Color? navColor,
    required String label,
  }) {
    return ServerMessagesNavSlot(
      builder: (context, unread) => _SidebarItem(
        key: const ValueKey('sidebar-server-messages'),
        icon: Icons.info_outline_rounded,
        label: label,
        baseColor: navColor,
        badgeCount: unread,
        focusNode: _serverMessagesFocusNode,
        showLabel: _showLabels,
        onPressed: () async {
          _onNavigate();
          await showServerMessagesDialog(context);
          if (!mounted) return;
          _markNavigationAwayFromSidebar();
          _serverMessagesFocusNode.requestFocus();
        },
      ),
    );
  }

  /// The friends row, or nothing when the server has no friends feature.
  Widget _friendsSidebarItem({
    required Color? navColor,
    required String label,
  }) {
    return FriendsNavSlot(
      builder: (context, badge) => _SidebarItem(
        key: const ValueKey('sidebar-friends'),
        icon: Icons.people_alt_rounded,
        label: label,
        baseColor: navColor,
        badgeCount: badge,
        focusNode: _friendsFocusNode,
        showLabel: _showLabels,
        onPressed: () async {
          _onNavigate();
          await FriendsNavSlot.open(context);
          if (!mounted) return;
          _markNavigationAwayFromSidebar();
          _friendsFocusNode.requestFocus();
        },
      ),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context);
    final showShuffle = _prefs.get(UserPreferences.showShuffleButton);
    final showGenres = _prefs.get(UserPreferences.showGenresButton);
    final showFavorites = _prefs.get(UserPreferences.showFavoritesButton);
    // Checked alongside the show* preferences, never written into them, since
    // those sync and would follow the account to the parent's other devices.
    final kidsMode = _kidsMode;
    final showLiveTv = _showLiveTvButton;
    final navLibraries = _navLibraries;
    final showLibraries =
        !kidsMode && _prefs.get(UserPreferences.showLibrariesInToolbar);
    final sunfinMode = SunfinStyle.enabled;
    final showFolders = _prefs.get(UserPreferences.enableFolderView);
    final showSyncPlay =
        !kidsMode &&
        _prefs.get(UserPreferences.syncPlayEnabled) &&
        _prefs.get(UserPreferences.showSyncPlayButton);
    final seerrPrefs = GetIt.instance<SeerrPreferences>();
    final seerrNavLabel = seerrPrefs.labelOrDefault(l10n.seerr);
    final clockBehavior = _prefs.get(UserPreferences.clockBehavior);
    // Sunfin: the clock lives in the page's top right, as in the reference design, so the
    // open rail doesn't show a second one.
    final showClock =
        !sunfinMode &&
        (clockBehavior == ClockBehavior.always ||
            clockBehavior == ClockBehavior.inMenus);
    return Column(
      children: [
        Visibility(
          visible: _isExpanded,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _buildUserSection(),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              var mainSlot = 0;
              Color? nextMainSidebarColor() {
                final c = AppColorScheme.navColorForSlot(mainSlot);
                if (c != null) mainSlot += 1;
                return c;
              }

              var librarySlot = 0;
              Color? nextLibrarySidebarColor() {
                final c = AppColorScheme.navColorForSlot(librarySlot);
                if (c != null) librarySlot += 1;
                return c;
              }

              final homeItem = _SidebarItem(
                  key: const ValueKey('sidebar-home'),
                  autoSelect: true,
                  icon: sunfinMode ? Symbols.home : Icons.home_rounded,
                  label: l10n.home,
                  baseColor: nextMainSidebarColor(),
                  focusNode: _homeFocusNode,
                  showLabel: _showLabels,
                  active: sunfinMode && _isActive(Destinations.home),
                  onPressed: () {
                    _onNavigate();
                    if (_isActive(Destinations.home)) {
                      homeRefreshBus.request();
                      _exitSidebarToContent();
                      return;
                    }
                    homeRefreshBus.requestAfterNavigation();
                    _markNavigationAwayFromSidebar();
                    context.go(Destinations.home);
                  },
                );
              final searchItem = _SidebarItem(
                  key: const ValueKey('sidebar-search'),
                  autoSelect: true,
                  icon: sunfinMode ? Symbols.search : Icons.search_rounded,
                  label: l10n.search,
                  baseColor: nextMainSidebarColor(),
                  focusNode: _searchFocusNode,
                  showLabel: _showLabels,
                  active: sunfinMode && _isActive(Destinations.search),
                  onPressed: () {
                    _onNavigate();
                    if (_isActive(Destinations.search)) {
                      _exitSidebarToContent();
                      return;
                    }
                    _markNavigationAwayFromSidebar();
                    context.navigateTopLevel(Destinations.search);
                  },
                );

              final items = <Widget>[
                // Sunfin order: Search, Home, then each library as its own row.
                if (sunfinMode) ...[
                  searchItem,
                  homeItem,
                  if (showLibraries)
                    for (final lib in navLibraries)
                      _SidebarItem(
                        key: ValueKey('sidebar-library-${lib.id}'),
                        autoSelect: true,
                        icon: sunfinLibraryIcon(lib.collectionType),
                        iconBuilder: sunfinLibraryIconBuilder(lib.collectionType),
                        label: lib.name,
                        baseColor: nextMainSidebarColor(),
                        focusNode: _libraryFocusNode(lib.id),
                        showLabel: _showLabels,
                        active: _isActiveRoute(_libraryRouteFor(lib)),
                        onPressed: () {
                          _onNavigate();
                          final route = _libraryRouteFor(lib);
                          if (_isActiveRoute(route)) {
                            _exitSidebarToContent();
                            return;
                          }
                          _markNavigationAwayFromSidebar();
                          context.navigateTopLevel(route);
                        },
                      ),
                ] else ...[
                  homeItem,
                  searchItem,
                ],
                if (showShuffle)
                  _SidebarItem(
                    key: const ValueKey('sidebar-shuffle'),
                    icon: Icons.shuffle_rounded,
                    label: l10n.shuffle,
                    baseColor: nextMainSidebarColor(),
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      showShuffleOverlay(context);
                    },
                  ),
                if (showGenres)
                  _SidebarItem(
                    key: const ValueKey('sidebar-genres'),
                    autoSelect: true,
                    baseColor: nextMainSidebarColor(),
                    iconBuilder: sunfinMode
                        ? sunfinGenresIcon
                        : (size, color) => Image.asset(
                            'assets/icons/genres.png',
                            width: size,
                            height: size,
                            color: color,
                          ),
                    label: l10n.genres,
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      if (_isActive(Destinations.allGenres)) {
                        _exitSidebarToContent();
                        return;
                      }
                      _markNavigationAwayFromSidebar();
                      context.navigateTopLevel(Destinations.allGenres);
                    },
                  ),
                if (showFavorites)
                  _SidebarItem(
                    key: const ValueKey('sidebar-favorites'),
                    autoSelect: true,
                    icon: Icons.favorite_rounded,
                    label: l10n.favorites,
                    baseColor: nextMainSidebarColor(),
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      if (_isActive(Destinations.allFavorites)) {
                        _exitSidebarToContent();
                        return;
                      }
                      _markNavigationAwayFromSidebar();
                      context.navigateTopLevel(Destinations.allFavorites);
                    },
                  ),
                if (showLiveTv)
                  _SidebarItem(
                    key: const ValueKey('sidebar-livetv'),
                    autoSelect: true,
                    icon: Icons.live_tv_rounded,
                    label: l10n.liveTv,
                    baseColor: nextMainSidebarColor(),
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      if (_isActive(Destinations.liveTvGuide)) {
                        _exitSidebarToContent();
                        return;
                      }
                      _markNavigationAwayFromSidebar();
                      context.navigateTopLevel(Destinations.liveTvGuide);
                    },
                  ),
                if (showFolders)
                  _SidebarItem(
                    key: const ValueKey('sidebar-folders'),
                    autoSelect: true,
                    icon: Icons.folder_rounded,
                    label: l10n.folders,
                    baseColor: nextMainSidebarColor(),
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      if (_isActive(Destinations.folderView)) {
                        _exitSidebarToContent();
                        return;
                      }
                      _markNavigationAwayFromSidebar();
                      context.navigateTopLevel(Destinations.folderView);
                    },
                  ),
                if (showSyncPlay)
                  _SidebarItem(
                    key: const ValueKey('sidebar-syncplay'),
                    icon: Icons.groups_rounded,
                    label: l10n.syncPlay,
                    baseColor: nextMainSidebarColor(),
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      _markNavigationAwayFromSidebar();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SyncPlayScreen(),
                        ),
                      );
                    },
                  ),
                if (!kidsMode &&
                    _prefs.get(UserPreferences.showSeerrButton) &&
                    GetIt.instance<PluginSyncService>().seerrAvailable)
                  _SidebarItem(
                    key: const ValueKey('sidebar-seerr'),
                    autoSelect: true,
                    baseColor: nextMainSidebarColor(),
                    iconBuilder: (size, color) => seerrPrefs.isSeerrVariant
                        ? SeerrIcon(size: size, color: color)
                        : SeerrIcon(size: size, color: color),
                    label: seerrNavLabel,
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      if (_isActive(Destinations.seerrDiscover)) {
                        _exitSidebarToContent();
                        return;
                      }
                      _markNavigationAwayFromSidebar();
                      context.navigateTopLevel(Destinations.seerrDiscover);
                    },
                  ),
                if (!sunfinMode && showLibraries && navLibraries.isNotEmpty) ...[
                  _SidebarItem(
                    key: const ValueKey('sidebar-libraries'),
                    baseColor: nextMainSidebarColor(),
                    iconBuilder: (size, color) => Image.asset(
                      'assets/icons/clapperboard.png',
                      width: size,
                      height: size,
                      color: color,
                      fit: BoxFit.contain,
                    ),
                    label: l10n.libraries,
                    showLabel: _showLabels,
                    trailing: _showLabels
                        ? AnimatedRotation(
                            turns: _librariesExpanded ? 0.5 : 0,
                            duration: _kExpandDuration,
                            child: Icon(
                              Icons.expand_more,
                              size:
                                  ((PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi)) &&
                                      !PlatformDetection.isTV)
                                  ? 18
                                  : 16,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          )
                        : null,
                    onPressed: () => setState(
                      () => _librariesExpanded = !_librariesExpanded,
                    ),
                  ),
                  AnimatedSize(
                    key: const ValueKey('sidebar-libraries-children'),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _librariesExpanded
                        ? Column(
                            children: navLibraries
                                .map(
                                  (lib) => _SidebarLibraryItem(
                                    key: ObjectKey(lib.id),
                                    label: lib.name,
                                    baseColor: nextLibrarySidebarColor(),
                                    showLabel: _showLabels,
                                    onPressed: () {
                                      _onNavigate();
                                      _markNavigationAwayFromSidebar();
                                      context.navigateTopLevel(
                                        libraryRoute(
                                          lib.id,
                                          lib.collectionType,
                                          lib.name,
                                          serverId: lib.serverId,
                                        ),
                                      );
                                    },
                                  ),
                                )
                                .toList(),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
                // The slot is taken here rather than inside the builder, so
                // the rows below keep their colour whether or not anything is
                // saved right now.
                if (DownloadsNavSlot.isOffered())
                  _downloadsSidebarItem(
                    navColor: nextMainSidebarColor(),
                    label: l10n.savedMedia,
                  ),
                // Only taken where the plugin has friends on, so on every
                // other server the rows after it keep their color.
                if (FriendsNavSlot.isOffered() && _friendsAvailable)
                  _friendsSidebarItem(
                    navColor: nextMainSidebarColor(),
                    label: l10n.friends,
                  ),
                // The slot is taken here rather than inside the builder, so the
                // settings row keeps its colour whether or not there are any
                // messages to show.
                if (_prefs.get(UserPreferences.showServerMessagesButton))
                  _serverMessagesSidebarItem(
                    navColor: nextMainSidebarColor(),
                    label: l10n.serverMessages,
                  ),
                if (_prefs.get(UserPreferences.showAdminButton) &&
                    adminAreaOffered(
                      isAdministrator:
                          _userRepo.currentUser?.isAdministrator ?? false,
                      kidsMode: kidsMode,
                    ))
                  _SidebarItem(
                    key: const ValueKey('sidebar-admin'),
                    autoSelect: true,
                    baseColor: nextMainSidebarColor(),
                    icon: sunfinMode
                        ? Symbols.admin_panel_settings
                        : Icons.admin_panel_settings,
                    label: l10n.administration,
                    showLabel: _showLabels,
                    onPressed: () {
                      _onNavigate();
                      _markNavigationAwayFromSidebar();
                      context.navigateTopLevel(Destinations.admin);
                    },
                  ),
                // Sunfin pins Settings to the bottom; see below the list.
                if (!sunfinMode) _settingsItem(l10n, nextMainSidebarColor()),
              ];

              return SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - 8),
                  ),
                  child: Column(
                    mainAxisAlignment: sunfinMode
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: items,
                  ),
                ),
              );
            },
          ),
        ),
        if (sunfinMode) _settingsItem(l10n, null),
        SidebarMusicCard(
          isExpanded: _showLabels,
          focusNode: _musicCardFocusNode,
        ),
        if (showClock)
          Visibility(
            visible: _showLabels,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ValueListenableBuilder<String>(
                    valueListenable: _currentTime,
                    builder: (context, time, _) {
                      return Text(
                        time,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          )
        else
          const SizedBox(height: 16),
      ],
    );
  }

  Widget _settingsItem(AppLocalizations l10n, Color? baseColor) {
    return _SidebarItem(
      key: const ValueKey('sidebar-settings'),
      icon: SunfinStyle.enabled ? Symbols.settings : Icons.settings_rounded,
      label: l10n.settings,
      baseColor: baseColor,
      focusNode: _settingsFocusNode,
      showLabel: _showLabels,
      onPressed: () async {
        _onNavigate();
        await SettingsPanel.open(
          context,
          const SettingsSidePanel(),
        );
        if (!mounted) return;
        _markNavigationAwayFromSidebar();
        _settingsFocusNode.requestFocus();
      },
    );
  }

  void _onNavigate() {
    if (_isMobile) _collapse();
  }

  void _exitSidebarToContent() {
    _collapse();
    if (PlatformDetection.isTV || (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      _restoreFocusOutsideSidebar();
    }
  }

  Widget _buildUserSection() {
    final user = _userRepo.currentUser;
    final initial = (user?.name.isNotEmpty == true)
        ? user!.name[0].toUpperCase()
        : '?';
    final fallback = Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
    );

    final tvCompact = PlatformDetection.isTV && !_showLabels;
    final innerPad = tvCompact ? 0.0 : 6.0;
    final isFocused = _profileFocusNode.hasFocus;

    final avatar = Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE5A00D), Color(0xFFB8740A)],
        ),
      ),
      child: ClipOval(
        child: _userImageUrl != null
            ? Image(
                // The server sends the avatar at its stored size, so decode
                // at the painted size instead of a full bitmap per user.
                image: ResizeImage.resizeIfNeeded(
                  ArtworkDecode.widthFor(
                    40,
                    MediaQuery.devicePixelRatioOf(context),
                  ),
                  null,
                  PacedNetworkImage(
                    _userImageUrl!,
                    headers: serverImageHeaders,
                  ),
                ),
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.all(innerPad),
      decoration: BoxDecoration(
        color: (PlatformDetection.isTV && isFocused && _showLabels)
            ? Colors.white
            : Colors.transparent,
        borderRadius: AppRadius.circular(24),
      ),
      child: Row(
        children: [
          avatar,
          if (_showLabels) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user?.name ?? '',
                style: TextStyle(
                  color: (PlatformDetection.isTV && isFocused)
                      ? Colors.black
                      : Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    // The reference design's collapsed rail is narrower than the avatar plus upstream's
    // margins, so the margin shrinks to centre the avatar in it.
    final sidePad = SunfinStyle.enabled && tvCompact
        ? math.max(0.0, (SunfinStyle.railCollapsedWidth - 40) / 2)
        : 8.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, 16, sidePad, 8),
      child: PlatformDetection.isTV
          ? Focus(
              focusNode: _profileFocusNode,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    _onNavigate();
                    showUserMenu(context);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    (SunfinStyle.enabled ? _searchFocusNode : _homeFocusNode)
                        .requestFocus();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: () {
                  _onNavigate();
                  showUserMenu(context);
                },
                child: content,
              ),
            )
          : GestureDetector(
              onTap: () {
                _onNavigate();
                showUserMenu(context);
              },
              child: content,
            ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData? icon;
  final Widget Function(double size, Color color)? iconBuilder;
  final String label;
  final bool showLabel;
  final VoidCallback onPressed;
  final Widget? trailing;
  final FocusNode? focusNode;
  final Color? baseColor;

  /// Unread count drawn as a small red circle on the icon. Zero draws nothing.
  final int badgeCount;

  /// The section on screen (Sunfin mode): gold icon on a faint tile while the
  /// row is not focused.
  final bool active;

  /// Rows that open a page open it once focus rests on them (Settings >
  /// Navigation > Auto-select). Rows that start something or open a menu,
  /// like Shuffle or Settings, never do.
  final bool autoSelect;

  const _SidebarItem({
    super.key,
    this.icon,
    this.iconBuilder,
    required this.label,
    required this.showLabel,
    required this.onPressed,
    this.trailing,
    this.focusNode,
    this.baseColor,
    this.badgeCount = 0,
    this.active = false,
    this.autoSelect = false,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  final _prefs = GetIt.instance<UserPreferences>();
  FocusNode? _internalNode;
  late final VoidCallback _focusListener;
  bool _isFocused = false;
  bool _isHovered = false;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalNode ??= FocusNode());

  bool get _tvCompact => PlatformDetection.isTV && !widget.showLabel;

  Timer? _autoSelectTimer;

  @override
  void initState() {
    super.initState();
    _focusListener = () {
      if (!mounted) return;
      final focused = _focusNode.hasFocus;
      if (focused != _isFocused) _scheduleAutoSelect(focused);
      setState(() => _isFocused = focused);
    };
    _focusNode.addListener(_focusListener);
    _isFocused = _focusNode.hasFocus;
  }

  /// Opens this row's page once focus has rested on it for the chosen time.
  /// Moving on before then cancels it, so passing over rows opens nothing.
  void _scheduleAutoSelect(bool focused) {
    _autoSelectTimer?.cancel();
    _autoSelectTimer = null;
    if (!focused || !widget.autoSelect || widget.active) return;
    if (!PlatformDetection.isTV) return;
    if (!_prefs.get(UserPreferences.sidebarAutoSelect)) return;
    final delay = Duration(
      milliseconds: _prefs.get(UserPreferences.sidebarAutoSelectDelayMs),
    );
    _autoSelectTimer = Timer(delay, () {
      _autoSelectTimer = null;
      if (mounted && _focusNode.hasFocus && !widget.active) {
        widget.onPressed();
      }
    });
  }

  @override
  void didUpdateWidget(_SidebarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalNode)?.removeListener(_focusListener);
      _focusNode.addListener(_focusListener);
      _isFocused = _focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _autoSelectTimer?.cancel();
    (widget.focusNode ?? _internalNode)?.removeListener(_focusListener);
    _internalNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktopSidebar =
        (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi)) && !PlatformDetection.isTV;
    final useBaseForFocus = widget.baseColor != null;
    final highlighted =
        (desktopSidebar && _isHovered) ||
        (PlatformDetection.isTV && _isFocused);
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final tvFocused = PlatformDetection.isTV && _isFocused;
    final baseColor = widget.baseColor ?? Colors.white.withValues(alpha: 0.6);
    final showActive = widget.active && !tvFocused;
    final fgColor = tvFocused
        ? Colors.black
        : showActive
        ? SunfinStyle.accent
        : highlighted
        ? (useBaseForFocus ? baseColor : focusColor)
        : baseColor;
    final iconSize = desktopSidebar ? 28.0 : 24.0;
    final iconSlotWidth = desktopSidebar ? 36.0 : 32.0;
    final labelFontSize = desktopSidebar ? 16.0 : 14.0;
    // Sunfin mode: the icon sits centred in the narrower collapsed rail.
    final compactPad = SunfinStyle.enabled
        ? math.max(0.0, (SunfinStyle.railCollapsedWidth - iconSlotWidth) / 2)
        : 12.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter)) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: desktopSidebar ? 44 : 40,
              padding: EdgeInsets.only(
                left: _tvCompact ? compactPad : 18,
                right: _tvCompact ? compactPad : 18,
              ),
              decoration: BoxDecoration(
                color: tvFocused
                    ? Colors.white
                    : showActive
                    ? Colors.white.withValues(alpha: 0.08)
                    : highlighted
                    ? (useBaseForFocus
                          ? baseColor.withValues(alpha: 0.12)
                          : focusColor.withValues(alpha: 0.12))
                    : Colors.transparent,
                borderRadius: PlatformDetection.isTV
                    ? AppRadius.circular(SunfinStyle.enabled ? 6 : 24)
                    : BorderRadius.zero,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: iconSlotWidth,
                    child: UnreadBadge(
                      count: widget.badgeCount,
                      child:
                          widget.iconBuilder?.call(iconSize, fgColor) ??
                          // The reference design's own thin-line drawings (sunfin_icons.dart).
                          (SunfinStyle.enabled
                              ? sunfinRailIcon(widget.icon, iconSize, fgColor)
                              : null) ??
                          (widget.icon != null
                              ? (SunfinStyle.enabled
                                    // Thin outline icons, as in the reference design.
                                    ? Icon(
                                        widget.icon!,
                                        size: iconSize,
                                        color: fgColor,
                                        weight: sunfinIconWeight,
                                      )
                                    : AdaptiveIcon(
                                        widget.icon!,
                                        size: iconSize,
                                        color: fgColor,
                                      ))
                              : const SizedBox.shrink()),
                    ),
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: fgColor,
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarLibraryItem extends StatefulWidget {
  final String label;
  final bool showLabel;
  final VoidCallback onPressed;
  final Color? baseColor;

  const _SidebarLibraryItem({
    super.key,
    required this.label,
    required this.showLabel,
    required this.onPressed,
    this.baseColor,
  });

  @override
  State<_SidebarLibraryItem> createState() => _SidebarLibraryItemState();
}

class _SidebarLibraryItemState extends State<_SidebarLibraryItem> {
  final _prefs = GetIt.instance<UserPreferences>();
  final _focusNode = FocusNode();
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktopSidebar =
        (PlatformDetection.isDesktop || (PlatformDetection.isWeb && !PlatformDetection.useMobileUi)) && !PlatformDetection.isTV;
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final baseColor = widget.baseColor ?? Colors.white.withValues(alpha: 0.5);
    final useBaseForFocus = widget.baseColor != null;
    final highlighted =
        (desktopSidebar && _isHovered) ||
        (PlatformDetection.isTV && _isFocused);
    final tvFocused = PlatformDetection.isTV && _isFocused;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter)) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: desktopSidebar ? 40 : 36,
              padding: EdgeInsets.only(
                left: desktopSidebar ? 64 : 58,
                right: 18,
              ),
              decoration: BoxDecoration(
                color: tvFocused
                    ? Colors.white
                    : highlighted
                    ? (useBaseForFocus
                          ? baseColor.withValues(alpha: 0.12)
                          : focusColor.withValues(alpha: 0.1))
                    : Colors.transparent,
                borderRadius: PlatformDetection.isTV
                    ? AppRadius.circular(24)
                    : BorderRadius.zero,
              ),
              alignment: Alignment.centerLeft,
              child: widget.showLabel
                  ? Text(
                      widget.label,
                      style: TextStyle(
                        color: tvFocused
                            ? Colors.black
                            : highlighted
                            ? (useBaseForFocus ? baseColor : focusColor)
                            : baseColor,
                        fontSize: desktopSidebar ? 15 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class SidebarMusicCard extends StatefulWidget {
  final bool isExpanded;
  final FocusNode? focusNode;
  const SidebarMusicCard({
    super.key,
    required this.isExpanded,
    this.focusNode,
  });

  @override
  State<SidebarMusicCard> createState() => _SidebarMusicCardState();
}

class _SidebarMusicCardState extends State<SidebarMusicCard> {
  final _manager = GetIt.instance<PlaybackManager>();
  final _clientFactory = GetIt.instance<MediaServerClientFactory>();
  StreamSubscription? _playSub;
  StreamSubscription? _queueSub;

  @override
  void initState() {
    super.initState();
    _playSub = _manager.state.playingStream.listen((_) {
      if (mounted) setState(() {});
    });
    _queueSub = _manager.queueService.queueChangedStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _playSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }

  AggregatedItem? get _currentItem {
    final raw = _manager.queueService.currentItem;
    return raw is AggregatedItem ? raw : null;
  }

  String? _artUrl(AggregatedItem item) {
    try {
      final client = _clientFactory.getClientIfExists(item.serverId) ??
          GetIt.instance<MediaServerClient>();
      final albumTag = item.albumPrimaryImageTag;
      final albumId = item.albumId;
      if (item.type == 'Audio' && albumTag != null && albumId != null) {
        return client.imageApi
            .getPrimaryImageUrl(albumId, maxHeight: 120, tag: albumTag);
      }
      if (item.primaryImageTag != null) {
        return client.imageApi
            .getPrimaryImageUrl(item.id, maxHeight: 120, tag: item.primaryImageTag);
      }
    } catch (_) {}
    return null;
  }

  Widget _buildCardButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool large = false,
  }) {
    return Focus(
      onKeyEvent: (node, event) {
        if (isActivateKey(event)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final diameter = large ? 38.0 : 32.0;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused
                    ? AppColorScheme.onSurface
                    : AppColorScheme.onSurface.withValues(alpha: 0.10),
              ),
              child: Icon(
                icon,
                size: large ? 22 : 18,
                color: focused ? AppColorScheme.surface : AppColorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    if (item == null || !item.isAudioLike) {
      return const SizedBox.shrink();
    }

    final isPlaying = _manager.state.isPlaying;
    final artUrl = _artUrl(item);

    if (!widget.isExpanded) {
      // Collapsed layout: show a single focusable circular avatar with the album art
      return Focus(
        onKeyEvent: (node, event) {
          if (isActivateKey(event)) {
            appRouter.push(Destinations.audioPlayer);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: () => appRouter.push(Destinations.audioPlayer),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: focused ? AppColorScheme.accent : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: focused
                          ? [
                              BoxShadow(
                                color: AppColorScheme.accent.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: ClipOval(
                      child: artUrl != null
                          ? OfflineAwareImage(
                              imageUrl: artUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppColorScheme.onSurface.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.music_note,
                                color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // Expanded layout: beautiful square card inside the sidebar
    final artist = item.artists.isNotEmpty
        ? item.artists.join(', ')
        : item.albumArtist ?? '';

    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;
    final border = isNeon
        ? Border.all(
            color: const Color(0xFF00F0FF),
            width: 1.5,
          )
        : Border.all(
            color: AppColorScheme.onSurface.withValues(alpha: 0.15),
            width: 1.0,
          );
    final boxShadow = isNeon
        ? const [
            BoxShadow(
              color: Color(0x3300F0FF),
              blurRadius: 8,
              spreadRadius: 1,
            )
          ]
        : null;

    final cardContent = GlassSurface(
      cornerRadius: 16,
      reinforced: true,
      fallbackColor: AppColorScheme.surfaceVariant.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => appRouter.push(Destinations.audioPlayer),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: artUrl != null
                        ? OfflineAwareImage(
                            imageUrl: artUrl,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: AppColorScheme.onSurface.withValues(alpha: 0.1),
                            child: Icon(
                              Icons.music_note,
                              color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          color: AppColorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (artist.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          style: TextStyle(
                            color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCardButton(
                icon: Icons.skip_previous,
                onPressed: _manager.previous,
              ),
              _buildCardButton(
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: isPlaying ? _manager.pause : _manager.resume,
                large: true,
              ),
              _buildCardButton(
                icon: Icons.skip_next,
                onPressed: _manager.next,
              ),
              _buildCardButton(
                icon: Icons.stop,
                onPressed: () => unawaited(_manager.stop(userInitiated: true)),
              ),
            ],
          ),
        ],
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: FocusTraversalGroup(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.circular(16),
              border: border,
              boxShadow: boxShadow,
            ),
            child: cardContent,
          ),
        ),
      ),
    );
  }
}
