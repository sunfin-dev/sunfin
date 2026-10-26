import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../preference/plex_locks.dart';
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

  /// The page's current tint along its left edge, top and bottom (from
  /// PlexBackdrop), so the rail beside it can take the same blend and show
  /// no seam. Null when no Plex backdrop has published one.
  static final ValueNotifier<(Color, Color)?> pageTint =
      ValueNotifier<(Color, Color)?>(null);

  /// How long the page tint takes to follow a new item (PlexBackdrop); the
  /// rail fades its colour over the same time so the two stay matched.
  static const tintDuration = PlexMotion.crossfade;

  /// Multiplies a 960-wide measurement onto Moonfin's TV canvas.
  static double s(double v960) => v960 * _k;

  // Sidebar contract (left_sidebar.dart / navigation_layout.dart). In Plex
  // mode the rail is solid and pushes the content right instead of covering
  // it, so every screen's content starts at the rail's right edge.

  /// Collapsed rail: icons only (Plex: ~80 px of 1920, icons centred at 40).
  static const railCollapsedWidth = 40.0 * _k;

  /// Expanded rail: the starting guess only. The rail measures its labels
  /// and fits the longest one (LeftSidebar.plexExpandedWidthNotifier); the
  /// user found Plex's fixed ~400 px twice too wide (2026-10-22).
  static const railExpandedWidth = 145.0;

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

  /// Always on TV, the 10-foot UI it was built for. Not a setting: the look
  /// is fixed, the left rail included (PlexLocks).
  static bool get enabled => PlexLocks.active;
}

/// Plexfin's one set of motion timings (user, 2026-10-26: quick and steady,
/// "not overly smooth like Apple", should feel like the app runs well). Short
/// ease-outs with no overshoot: things start at speed and settle, so the app
/// answers the remote at once.
abstract final class PlexMotion {
  /// A focus ring or poster growing onto the focused item.
  static const focus = Duration(milliseconds: 120);

  /// Things moving: rows and pages scrolling, the rail opening.
  static const move = Duration(milliseconds: 200);

  /// Text and controls fading in or out.
  static const fade = Duration(milliseconds: 160);

  /// Backdrop art and the page tint following the focused item.
  static const crossfade = Duration(milliseconds: 280);

  /// One page replacing another.
  static const page = Duration(milliseconds: 240);

  static const curve = Curves.easeOutCubic;

  /// A new page fades in once its first, heavy frames are built, so the
  /// part of the fade that is seen runs smooth.
  static const pageIn = Interval(0.25, 1, curve: Curves.easeOutCubic);

  /// A closing page fades straight out.
  static const pageOut = Curves.easeInCubic;
}

/// Plex's sidebar icons are thin outlines; Material Symbols drawn at this
/// weight match them (plain Material Icons ignore it).
const double plexIconWeight = 300;

/// The Movies icon the user picked (round 2, option 3): Plex's film strip
/// with a middle frame line and two sprocket ticks per half. Drawn black and
/// recoloured, so it follows the row's colour like the font icons.
const _plexMoviesSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<g fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round" '
    'stroke-linejoin="round">'
    '<rect x="3.5" y="3.5" width="17" height="17" rx="1.5"/>'
    '<path d="M7.5 3.5v17M16.5 3.5v17M3.5 12h17"/>'
    '<path d="M3.5 6.4h4M3.5 9.2h4M3.5 14.8h4M3.5 17.6h4'
    'M16.5 6.4h4M16.5 9.2h4M16.5 14.8h4M16.5 17.6h4"/>'
    '</g></svg>';

Widget plexMoviesIcon(double size, Color color) => SvgPicture.string(
  _plexMoviesSvg,
  width: size,
  height: size,
  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
);

/// Sidebar icon builder for libraries drawn from SVG rather than the icon
/// font; null when [plexLibraryIcon] covers the type.
Widget Function(double size, Color color)? plexLibraryIconBuilder(
  String? collectionType,
) => (collectionType ?? '').toLowerCase() == 'movies' ? plexMoviesIcon : null;

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
