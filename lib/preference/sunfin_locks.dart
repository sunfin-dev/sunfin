import 'package:flutter/foundation.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../util/platform_detection.dart';
import 'preference_constants.dart';
import 'user_preferences.dart';

/// Sunfin: the look is the product, so every setting that changes how the
/// app looks is fixed to its Sunfin value. What the user
/// sees stays theirs: which sidebar items, libraries, home rows and detail
/// buttons show up.
///
/// [UserPreferences.get] answers these with the locked value whatever is
/// stored, so an old choice can't bring another look back. The stored
/// values themselves are left alone.
///
/// Screens not reskinned yet are held at their closest match to Sunfin until
/// they get their own Sunfin layout.
abstract final class SunfinLocks {
  /// The Sunfin look exists on the TV layout only.
  static bool get active => PlatformDetection.isTV;

  /// Per-row image types on the home screen, one preference per row.
  static const _lockedPrefixes = ['homeRowImageType_'];

  static final Map<String, Object?> _values = () {
    final values = <String, Object?>{};
    void lock<T>(Preference<T> pref, [T? value]) =>
        values[pref.key] = value ?? pref.defaultValue;

    // Navigation: the Sunfin rail.
    lock(UserPreferences.navbarPosition, NavbarPosition.left);
    lock(UserPreferences.bottomNavbarStyle);
    lock(UserPreferences.navbarColor);
    lock(UserPreferences.navbarOpacity);
    lock(UserPreferences.navbarAlwaysExpanded);

    // Home: the Sunfin header and poster rows replace these. Classic rows are
    // what the Sunfin rows are built on, and they keep the detail page's rows
    // on posters too, as in the reference design.
    lock(UserPreferences.homeRowsStyle, HomeRowsStyle.v1);
    lock(UserPreferences.modernCardsOnMyMediaRow);
    lock(UserPreferences.posterSize);
    lock(UserPreferences.modernHomeRowsPadding);
    lock(UserPreferences.classicHomeRowsPadding);
    lock(UserPreferences.fullScreenRows);
    lock(UserPreferences.seriesThumbnailsEnabled);
    lock(UserPreferences.homeRowInfoOverlay);
    lock(UserPreferences.hideHomeMediaDescription);

    // Theme and style.
    lock(UserPreferences.visualTheme, VisualThemeId.moonfin);
    lock(UserPreferences.customThemeId, '');
    lock(UserPreferences.interfaceStyle);
    lock(UserPreferences.interfaceLayout);
    lock(UserPreferences.glassQuality);
    lock(UserPreferences.focusColor);
    lock(UserPreferences.oledMode);
    lock(UserPreferences.backdropEnabled);
    lock(UserPreferences.browsingBackgroundBlurAmount);
    lock(UserPreferences.cardFocusExpansion);
    lock(UserPreferences.delayCardExpansionOnRapidScroll);
    lock(UserPreferences.desktopUiScale);
    lock(UserPreferences.pageTransitionSpeed);
    lock(UserPreferences.navigationAnimationSpeed);
    lock(UserPreferences.modernCardTransitionSpeed);
    // The reference design shows the time in the top right on every screen, 12-hour.
    lock(UserPreferences.clockBehavior, ClockBehavior.always);
    lock(UserPreferences.use24HourClock, false);
    // The reference design: a check on watched items, a count on shows with unwatched ones.
    lock(UserPreferences.watchedIndicatorBehavior, WatchedIndicatorBehavior.always);

    // Visual extras.
    lock(UserPreferences.seasonalSurprise);
    lock(UserPreferences.seasonalDensity);
    lock(UserPreferences.loadingAnimationImage);
    lock(UserPreferences.loadingAnimationSize);
    lock(UserPreferences.loadingAnimationPosition);
    lock(UserPreferences.loadingAnimationSpeed);
    lock(UserPreferences.showLoadingAnimationText);

    // Details: Nouveau is the closest to the reference design's page (text left, art top
    // right, sections stacked below) until the Sunfin details page exists.
    lock(UserPreferences.detailScreenStyle, DetailScreenStyle.nouveau);
    lock(UserPreferences.detailsBackgroundBlurAmount);
    lock(UserPreferences.personalRatingStyle, PersonalRatingStyle.stars);

    // Libraries: The reference design's grid has a plain tinted page, no details header and
    // a short line under each poster.
    lock(UserPreferences.hideBackdropsInLibraries, true);
    lock(UserPreferences.showMediaDetailsOnLibraryPage, false);
    lock(UserPreferences.useDetailedSubHeadings, false);

    return values;
  }();

  /// Sunfin's own rules rather than its look, so they hold on every device,
  /// the phone and the PC included.
  static final Map<String, Object?> _everywhere = {
    // Settings move between devices only when the user says so, through
    // Transfer settings; nothing syncs them on its own. The plugin's other
    // services stay on.
    UserPreferences.pluginSyncEnabled.key: false,
  };

  /// Lets the tests of the plugin's own settings sync turn it on.
  @visibleForTesting
  static bool debugSyncAllowed = false;

  static bool _heldEverywhere(String key) =>
      !debugSyncAllowed && _everywhere.containsKey(key);

  /// True when [key] is held at its Sunfin value.
  static bool isLocked(String key) =>
      _heldEverywhere(key) ||
      (active &&
          (_values.containsKey(key) ||
              _lockedPrefixes.any((prefix) => key.startsWith(prefix))));

  /// The Sunfin value for [pref]; only meaningful when [isLocked].
  static T valueOf<T>(Preference<T> pref) => _heldEverywhere(pref.key)
      ? _everywhere[pref.key] as T
      : _values.containsKey(pref.key)
      ? _values[pref.key] as T
      : pref.defaultValue;
}
