import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../preference/sunfin_locks.dart';
import '../../util/tv_ui_scale.dart';

/// Shared look of the fork's Sunfin mode, measured from the reference design's
/// Android TV client at 1920x1080.
///
/// Moonfin lays every TV screen out on a [kTvDesignWidth] (1150) wide canvas
/// and scales it to the panel (util/tv_ui_scale.dart). The measurements were
/// taken as 960-wide values (screenshot px / 2), so each is multiplied by
/// [_k] to land on Moonfin's canvas.
abstract final class SunfinStyle {
  static const _k = kTvDesignWidth / 960;

  /// [_k] for const expressions elsewhere (e.g. `20.0 * SunfinStyle.k`).
  static const k = _k;

  /// The reference design's gold, used for the active sidebar section and progress bars.
  static const accent = Color(0xFFE5A00D);

  /// Base page colour the backdrop fades into when no art tint is known.
  static const background = Color(0xFF1F2326);

  /// The page's current tint along its left edge, top and bottom (from
  /// SunfinBackdrop), so the rail beside it can take the same blend and show
  /// no seam. Null when no Sunfin backdrop has published one.
  static final ValueNotifier<(Color, Color)?> pageTint =
      ValueNotifier<(Color, Color)?>(null);

  /// How long the page tint takes to follow a new item (SunfinBackdrop); the
  /// rail fades its colour over the same time so the two stay matched.
  static const tintDuration = SunfinMotion.crossfade;

  /// Multiplies a 960-wide measurement onto Moonfin's TV canvas.
  static double s(double v960) => v960 * _k;

  // Sidebar contract (left_sidebar.dart / navigation_layout.dart). In the reference design
  // mode the rail is solid and pushes the content right instead of covering
  // it, so every screen's content starts at the rail's right edge.

  /// Collapsed rail: icons only (the reference design: ~80 px of 1920, icons centred at 40).
  static const railCollapsedWidth = 40.0 * _k;

  /// Expanded rail: the starting guess only. The rail measures its labels
  /// and fits the longest one (LeftSidebar.sunfinExpandedWidthNotifier); the
  /// user found the reference design's fixed ~400 px twice too wide (2026-10-22).
  static const railExpandedWidth = 145.0;

  // Home layout contract (sunfin_home_header.dart, sunfin_backdrop.dart and the
  // Sunfin branch of home_screen.dart). x values are from the content's left
  // edge, i.e. the rail's right edge.

  /// Left edge of the header text and of the first poster in each row,
  /// measured from the rail (the reference design: 112 px of 1920 from the screen edge,
  /// minus the 80 px rail).
  static const contentInset = 16.0 * _k;

  /// Top of the header title block.
  static const headerTop = 68.0 * _k;

  /// Where the focused row's title sits; the header owns everything above.
  static const rowsTop = 228.0 * _k;

  /// Header text column width (the reference design wraps the summary at ~46% of the screen).
  static const headerTextWidth = 400.0 * _k;

  /// The sharp backdrop: right-aligned to the screen, 16:9, fades out to the
  /// left and bottom. The reference design's box is 1232 x 693 of a 1920 x 1080 screen, the
  /// same on home and every details page (measured 2026-11-03 by matching
  /// The reference design's own art to its screenshots).
  static const backdropWidth = 616.0 * _k;
  static const backdropHeight = 346.5 * _k;

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
  /// is fixed, the left rail included (SunfinLocks).
  static bool get enabled => SunfinLocks.active;
}

/// Sunfin's one set of motion timings (user, 2026-10-26: quick and steady,
/// "not overly smooth like Apple", should feel like the app runs well). Short
/// ease-outs with no overshoot: things start at speed and settle, so the app
/// answers the remote at once.
abstract final class SunfinMotion {
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

/// The reference design's sidebar icons are thin outlines; Material Symbols drawn at this
/// weight match them (plain Material Icons ignore it).
const double sunfinIconWeight = 300;

/// The Movies icon the user picked (round 2, option 3): the reference design's film strip
/// with a middle frame line and two sprocket ticks per half. Drawn black and
/// recoloured, so it follows the row's colour like the font icons.
const _sunfinMoviesSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<g fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round" '
    'stroke-linejoin="round">'
    '<rect x="3.5" y="3.5" width="17" height="17" rx="1.5"/>'
    '<path d="M7.5 3.5v17M16.5 3.5v17M3.5 12h17"/>'
    '<path d="M3.5 6.4h4M3.5 9.2h4M3.5 14.8h4M3.5 17.6h4'
    'M16.5 6.4h4M16.5 9.2h4M16.5 14.8h4M16.5 17.6h4"/>'
    '</g></svg>';

Widget sunfinMoviesIcon(double size, Color color) => SvgPicture.string(
  _sunfinMoviesSvg,
  width: size,
  height: size,
  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
);

/// Sidebar icon builder for libraries drawn from SVG rather than the icon
/// font; null when [sunfinLibraryIcon] covers the type.
Widget Function(double size, Color color)? sunfinLibraryIconBuilder(
  String? collectionType,
) => (collectionType ?? '').toLowerCase() == 'movies' ? sunfinMoviesIcon : null;

/// Sidebar icon per library type, as in the reference design: a film strip for movies, a
/// monitor on a stand for shows, a note for music.
IconData sunfinLibraryIcon(String? collectionType) =>
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
