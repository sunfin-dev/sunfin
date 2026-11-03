import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Sunfin rail icons, drawn to the reference design's sidebar (reference 01): thin 1.5
/// outlines on a 24 grid like the Movies icon the user picked, with the reference design's
/// solid gear for Settings (user, 2026-10-26: "redraw the rest to match").
/// Drawn black and recoloured, so they follow the row's colour like the font
/// icons did.

const _open =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<g fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round" '
    'stroke-linejoin="round">';
const _close = '</g></svg>';

const _home =
    '$_open<path d="M3.75 10.6 12 3.75l8.25 6.85v9.65h-5.5v-4.75a2.75 2.75 '
    '0 0 0-5.5 0v4.75h-5.5z"/>$_close';

const _search =
    '$_open<circle cx="10.5" cy="10.5" r="6.75"/>'
    '<path d="M15.4 15.4 20.5 20.5"/>$_close';

/// A monitor on a short stand bar, the reference design's TV Shows icon.
const _tv =
    '$_open<rect x="2.75" y="4.25" width="18.5" height="12.5" rx="1.25"/>'
    '<path d="M8 20.25h8"/>$_close';

/// The reference design's beamed pair of notes, heads filled.
const _music =
    '$_open<path d="M8.75 17.5V4.75h10.5V17.5M8.75 7.75h10.5"/>'
    '<circle cx="6.6" cy="17.6" r="2.15" fill="#000" stroke="none"/>'
    '<circle cx="17.1" cy="17.6" r="2.15" fill="#000" stroke="none"/>$_close';

const _book =
    '$_open<path d="M12 6.5C10 5 7 4.5 3.75 4.75v13.5C7 18 10 18.5 12 20c2-1.5 '
    '5-2 8.25-1.75V4.75C17 4.5 14 5 12 6.5zM12 6.5V20"/>$_close';

const _liveTv =
    '$_open<rect x="2.75" y="7.25" width="18.5" height="12.5" rx="1.25"/>'
    '<path d="M8.5 3.25 12 6.75l3.5-3.5"/>$_close';

const _photos =
    '$_open<rect x="3.5" y="4.5" width="17" height="15" rx="1.5"/>'
    '<path d="M3.5 16.5l5-5 4 4 2.5-2.5 5.5 5.5"/>'
    '<circle cx="15.5" cy="9" r="1.5"/>$_close';

const _collections =
    '$_open<rect x="6.5" y="6.5" width="14" height="14" rx="1.5"/>'
    '<path d="M3.5 17V5A1.5 1.5 0 0 1 5 3.5h12"/>$_close';

const _videoLibrary =
    '$_open<rect x="3.5" y="5.5" width="17" height="13" rx="1.5"/>'
    '<path d="M10.25 9.5v5l4.25-2.5z"/>$_close';

const _shuffle =
    '$_open<path d="M3.5 7h3.2c2.3 0 3.6 1 4.8 3l1 1.9c1.2 2 2.5 3.1 4.8 3.1h3.2'
    'M3.5 17h3.2c1.6 0 2.7-.5 3.6-1.5M13.7 8.5c.9-1 2-1.5 3.6-1.5h3.2'
    'M18 4.5 20.5 7 18 9.5M18 14.5l2.5 2.5-2.5 2.5"/>$_close';

const _heart =
    '$_open<path d="M12 20.25s-8.25-4.9-8.25-10.75A4.5 4.5 0 0 1 12 6.9a4.5 4.5 '
    '0 0 1 8.25 2.6c0 5.85-8.25 10.75-8.25 10.75z"/>$_close';

const _folder =
    '$_open<path d="M3.5 6.5A1.5 1.5 0 0 1 5 5h4.5l2 2.25H19a1.5 1.5 0 0 1 1.5 '
    '1.5v9.75A1.5 1.5 0 0 1 19 20H5a1.5 1.5 0 0 1-1.5-1.5z"/>$_close';

const _people =
    '$_open<circle cx="9" cy="8.5" r="3.25"/>'
    '<path d="M3 19.5c.5-3.3 3-5.25 6-5.25s5.5 1.95 6 5.25'
    'M15.5 5.5a3.25 3.25 0 0 1 0 6.25M17.5 14.6c2 .7 3.2 2.4 3.5 4.9"/>'
    '$_close';

const _download =
    '$_open<path d="M12 3.5v11M7.5 10 12 14.5 16.5 10'
    'M4 15.5v3A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-3"/>$_close';

const _info =
    '$_open<circle cx="12" cy="12" r="8.75"/><path d="M12 11v5.5"/>'
    '<circle cx="12" cy="7.75" r=".9" fill="#000" stroke="none"/>$_close';

const _genres =
    '$_open<circle cx="7.5" cy="7.5" r="3.5"/><path d="M16.5 3.75 20.25 10.5h-7.5z"/>'
    '<rect x="4" y="13.5" width="7" height="7" rx="1"/>'
    '<circle cx="16.75" cy="17" r="3.5"/>$_close';

/// The reference design's gear is solid with a round hole.
const _settings =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path fill="#000" fill-rule="evenodd" d="M19.54 12.93 L21.75 14.21 '
    'L20.46 17.33 L17.99 16.68 L16.68 17.99 L17.33 20.46 L14.21 21.75 '
    'L12.93 19.54 L11.07 19.54 L9.79 21.75 L6.67 20.46 L7.32 17.99 '
    'L6.01 16.68 L3.54 17.33 L2.25 14.21 L4.46 12.93 L4.46 11.07 '
    'L2.25 9.79 L3.54 6.67 L6.01 7.32 L7.32 6.01 L6.67 3.54 L9.79 2.25 '
    'L11.07 4.46 L12.93 4.46 L14.21 2.25 L17.33 3.54 L16.68 6.01 '
    'L17.99 7.32 L20.46 6.67 L21.75 9.79 L19.54 11.07Z'
    'M15.25 12a3.25 3.25 0 1 0-6.5 0 3.25 3.25 0 1 0 6.5 0Z"/></svg>';

/// The rail's font icons, by the icon the row asks for.
final Map<IconData, String> _byIcon = {
  Symbols.home: _home,
  Icons.home_rounded: _home,
  Symbols.search: _search,
  Icons.search_rounded: _search,
  Symbols.settings: _settings,
  Icons.settings_rounded: _settings,
  Symbols.desktop_windows: _tv,
  Symbols.music_note: _music,
  Symbols.menu_book: _book,
  Symbols.live_tv: _liveTv,
  Icons.live_tv_rounded: _liveTv,
  Symbols.photo_library: _photos,
  Symbols.collections_bookmark: _collections,
  Symbols.video_library: _videoLibrary,
  Icons.shuffle_rounded: _shuffle,
  Icons.favorite_rounded: _heart,
  Icons.folder_rounded: _folder,
  Icons.groups_rounded: _people,
  Icons.people_alt_rounded: _people,
  Icons.download_for_offline: _download,
  Icons.info_outline_rounded: _info,
};

Widget _svg(String svg, double size, Color color) => SvgPicture.string(
  svg,
  width: size,
  height: size,
  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
);

/// The Sunfin drawing for a rail icon, or null when there is none for it.
Widget? sunfinRailIcon(IconData? icon, double size, Color color) {
  final svg = icon == null ? null : _byIcon[icon];
  return svg == null ? null : _svg(svg, size, color);
}

/// Genres has a picture rather than a font icon upstream.
Widget sunfinGenresIcon(double size, Color color) => _svg(_genres, size, color);
