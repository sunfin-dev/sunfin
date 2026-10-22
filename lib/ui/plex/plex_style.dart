import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';

/// Shared look of the fork's Plex-style mode, measured from the Plex Android
/// TV client at 1920x1080 (Projects/Plex Clone/reference/plex). The Shield
/// renders at devicePixelRatio 2, so every value here is in logical pixels of
/// a 960x540 screen (screenshot pixels / 2).
abstract final class PlexStyle {
  /// Plex's gold, used for the active sidebar section and progress bars.
  static const accent = Color(0xFFE5A00D);

  /// Base page colour the backdrop fades into when no art tint is known.
  static const background = Color(0xFF1F2326);

  // Home layout contract (shared by plex_home_header.dart, plex_backdrop.dart
  // and the Plex branch of home_screen.dart).

  /// Top of the header title block.
  static const headerTop = 68.0;

  /// Where the focused row's title sits; the header owns everything above.
  static const rowsTop = 228.0;

  /// Header text column width (Plex wraps the summary at ~46% of the screen).
  static const headerTextWidth = 400.0;

  /// The sharp backdrop: right-aligned, 16:9, fades out to the left and bottom.
  static const backdropWidth = 600.0;
  static const backdropHeight = 338.0;

  /// Portrait poster cards on every home row (episodes use the series poster).
  static const posterWidth = 110.0;
  static const posterHeight = 165.0;
  static const posterGap = 14.0;
  static const focusedPosterScale = 1.12;
  static const focusBorderWidth = 1.5;
  static const posterRadius = 4.0;

  /// Row title, e.g. "Continue Watching".
  static const rowTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 16,
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

/// Sidebar icon per library type, outlined like Plex's.
IconData plexLibraryIcon(String? collectionType) =>
    switch ((collectionType ?? '').toLowerCase()) {
      'movies' => Icons.movie_outlined,
      'tvshows' => Icons.tv_outlined,
      'music' => Icons.music_note_outlined,
      'books' || 'audiobooks' => Icons.menu_book_outlined,
      'livetv' => Icons.live_tv_outlined,
      'homevideos' || 'photos' => Icons.photo_library_outlined,
      'boxsets' => Icons.collections_bookmark_outlined,
      _ => Icons.video_library_outlined,
    };
