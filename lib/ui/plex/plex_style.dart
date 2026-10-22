import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';
import '../../util/tv_ui_scale.dart';

/// Shared look of the fork's Plex-style mode, measured from the Plex Android
/// TV client at 1920x1080 (Projects/Plex Clone/reference/plex).
///
/// Moonfin lays every TV screen out on a [kTvDesignWidth] (1150) wide canvas
/// and scales it to the panel (util/tv_ui_scale.dart). The measurements were
/// taken as 960-wide values (screenshot px / 2), so each is multiplied by
/// [_k] to land on Moonfin's canvas.
abstract final class PlexStyle {
  static const _k = kTvDesignWidth / 960;

  /// [_k] for const expressions elsewhere (e.g. `20.0 * PlexStyle.k`).
  static const k = _k;

  /// Plex's gold, used for the active sidebar section and progress bars.
  static const accent = Color(0xFFE5A00D);

  /// Base page colour the backdrop fades into when no art tint is known.
  static const background = Color(0xFF1F2326);

  /// Multiplies a 960-wide measurement onto Moonfin's TV canvas.
  static double s(double v960) => v960 * _k;

  // Sidebar contract (left_sidebar.dart / navigation_layout.dart). In Plex
  // mode the rail is solid and pushes the content right instead of covering
  // it, so every screen's content starts at the rail's right edge.

  /// Collapsed rail: icons only (Plex: ~80 px of 1920, icons centred at 40).
  static const railCollapsedWidth = 40.0 * _k;

  /// Expanded rail with labels (Plex: ~400 px of 1920).
  static const railExpandedWidth = 200.0 * _k;

  // Home layout contract (plex_home_header.dart, plex_backdrop.dart and the
  // Plex branch of home_screen.dart). x values are from the content's left
  // edge, i.e. the rail's right edge.

  /// Left edge of the header text and of the first poster in each row,
  /// measured from the rail (Plex: 112 px of 1920 from the screen edge,
  /// minus the 80 px rail).
  static const contentInset = 16.0 * _k;

  /// Top of the header title block.
  static const headerTop = 68.0 * _k;

  /// Where the focused row's title sits; the header owns everything above.
  static const rowsTop = 228.0 * _k;

  /// Header text column width (Plex wraps the summary at ~46% of the screen).
  static const headerTextWidth = 400.0 * _k;

  /// The sharp backdrop: right-aligned to the screen, 16:9, fades out to the
  /// left and bottom.
  /// Plex's art reaches about two thirds down the screen with a long fade
  /// into the rows (reference 15-home-episode-mirror.png).
  static const backdropWidth = 600.0 * _k;
  static const backdropHeight = 372.0 * _k;

  /// Portrait poster cards on every home row (episodes use the series poster).
  static const posterWidth = 110.0 * _k;
  static const posterHeight = 165.0 * _k;
  static const posterGap = 14.0 * _k;
  static const focusedPosterScale = 1.12;
  static const focusBorderWidth = 1.5 * _k;
  static const posterRadius = 4.0 * _k;

  /// Row title, e.g. "Continue Watching".
  static const rowTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 16 * _k,
    fontWeight: FontWeight.w700,
  );

  /// Only on TV with the left sidebar: the Plex layout is a 10-foot UI built
  /// around a left rail; with the top toolbar the header would sit under it.
  static bool get enabled {
    if (!PlatformDetection.isTV) return false;
    final prefs = GetIt.instance<UserPreferences>();
    return prefs.get(UserPreferences.plexMode) &&
        prefs.get(UserPreferences.navbarPosition) == NavbarPosition.left;
  }
}

/// Plex's sidebar icons are thin outlines; Material Symbols drawn at this
/// weight match them (plain Material Icons ignore it).
const double plexIconWeight = 300;

/// Sidebar icon per library type, as in Plex: a film strip for movies, a
/// monitor on a stand for shows, a note for music.
IconData plexLibraryIcon(String? collectionType) =>
    switch ((collectionType ?? '').toLowerCase()) {
      'movies' => Symbols.theaters,
      'tvshows' => Symbols.desktop_windows,
      'music' => Symbols.music_note,
      'books' || 'audiobooks' => Symbols.menu_book,
      'livetv' => Symbols.live_tv,
      'homevideos' || 'photos' => Symbols.photo_library,
      'boxsets' => Symbols.collections_bookmark,
      _ => Symbols.video_library,
    };
