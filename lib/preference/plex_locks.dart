import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../util/platform_detection.dart';
import 'preference_constants.dart';
import 'user_preferences.dart';

/// Plexfin: the look is the product, so every setting that changes how the
/// app looks is fixed to its Plex value (user, 2026-10-23). What the user
/// sees stays theirs: which sidebar items, libraries, home rows and detail
/// buttons show up.
///
/// [UserPreferences.get] answers these with the locked value whatever is
/// stored, so neither an old choice nor a profile synced from the stock
/// Moonfin app can bring another look back. The stored values themselves
/// are left alone and are what the plugin sync pushes, so Plexfin never
/// rewrites the stock app's settings with the Plex ones.
///
/// Screens not reskinned yet are held at their closest match to Plex until
/// they get their own Plex layout.
abstract final class PlexLocks {
  /// The Plex look exists on the TV layout only.
  static bool get active => PlatformDetection.isTV;

  /// Per-row image types on the home screen, one preference per row.
  static const _lockedPrefixes = ['homeRowImageType_'];

  static final Map<String, Object?> _values = () {
    final values = <String, Object?>{};
    void lock<T>(Preference<T> pref, [T? value]) =>
        values[pref.key] = value ?? pref.defaultValue;

    // Navigation: the Plex rail.
    lock(UserPreferences.navbarPosition, NavbarPosition.left);
    lock(UserPreferences.bottomNavbarStyle);
    lock(UserPreferences.navbarColor);
    lock(UserPreferences.navbarOpacity);
    lock(UserPreferences.navbarAlwaysExpanded);

    // Home: the Plex header and poster rows replace these. Classic rows are
    // what the Plex rows are built on, and they keep the detail page's rows
    // on posters too, as in Plex.
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
    // Plex shows the time in the top right on every screen, 12-hour.
    lock(UserPreferences.clockBehavior, ClockBehavior.always);
    lock(UserPreferences.use24HourClock, false);
    // Plex: a check on watched items, a count on shows with unwatched ones.
    lock(UserPreferences.watchedIndicatorBehavior, WatchedIndicatorBehavior.always);

    // Visual extras.
    lock(UserPreferences.seasonalSurprise);
    lock(UserPreferences.seasonalDensity);
    lock(UserPreferences.loadingAnimationImage);
    lock(UserPreferences.loadingAnimationSize);
    lock(UserPreferences.loadingAnimationPosition);
    lock(UserPreferences.loadingAnimationSpeed);
    lock(UserPreferences.showLoadingAnimationText);

    // Details: Nouveau is the closest to Plex's page (text left, art top
    // right, sections stacked below) until the Plex details page exists.
    lock(UserPreferences.detailScreenStyle, DetailScreenStyle.nouveau);
    lock(UserPreferences.detailsBackgroundBlurAmount);
    lock(UserPreferences.personalRatingStyle, PersonalRatingStyle.stars);

    // Libraries: Plex's grid has a plain tinted page, no details header and
    // a short line under each poster.
    lock(UserPreferences.hideBackdropsInLibraries, true);
    lock(UserPreferences.showMediaDetailsOnLibraryPage, false);
    lock(UserPreferences.useDetailedSubHeadings, false);

    return values;
  }();

  /// True when [key] is held at its Plex value.
  static bool isLocked(String key) =>
      active &&
      (_values.containsKey(key) ||
          _lockedPrefixes.any((prefix) => key.startsWith(prefix)));

  /// The Plex value for [pref]; only meaningful when [isLocked].
  static T valueOf<T>(Preference<T> pref) =>
      _values.containsKey(pref.key) ? _values[pref.key] as T : pref.defaultValue;
}
