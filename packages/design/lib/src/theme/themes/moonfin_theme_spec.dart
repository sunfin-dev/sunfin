import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../theme_spec.dart';

// Plexfin: Plex gold where Moonfin had Jellyfin cyan, with dark text on the
// gold as Plex draws it.
const _plexGold = Color(0xFFE5A00D);
const _onPlexGold = Color(0xFF1F1F1F);

const moonfinThemeSpec = ThemeSpec(
  id: 'moonfin',
  displayName: 'Plexfin',
  colors: ThemeColorTokens(
    background: AppColors.black700,
    onBackground: AppColors.white,
    surface: AppColors.black500,
    onSurface: AppColors.white,
    surfaceVariant: Color(0xFF252525),
    scrim: Color(0xCC000000),
    accent: _plexGold,
    onAccent: _onPlexGold,
    buttonNormal: Color(0xFF2A2A2A),
    buttonFocused: AppColors.white,
    buttonDisabled: Color(0xFF1E1E1E),
    buttonActive: Color(0xFF3A3A3A),
    onButtonNormal: AppColors.white,
    onButtonFocused: _onPlexGold,
    onButtonDisabled: Color(0xFF666666),
    inputBackground: Color(0xFF2A2A2A),
    inputFocused: Color(0xFF3A3A3A),
    inputBorder: Color(0xFF404040),
    inputBorderFocused: _plexGold,
    rangeTrack: Color(0xFF404040),
    rangeProgress: _plexGold,
    rangeThumb: _plexGold,
    seekbarBuffered: Color(0x80FFFFFF),
    badgeBackground: _plexGold,
    onBadge: _onPlexGold,
    badgeUnplayed: _plexGold,
    badgeWatched: AppColors.green500,
    recordingActive: AppColors.red500,
    recordingScheduled: AppColors.orange500,
  ),
  borders: ThemeBorderTokens(
    cardBorder: BorderSide(color: Colors.transparent),
    chipBorder: BorderSide(color: Color(0x40FFFFFF)),
    focusBorder: BorderSide(color: _plexGold, width: 2),
    cardRadius: BorderRadius.all(Radius.circular(8)),
    chipRadius: BorderRadius.all(Radius.circular(999)),
    chipBackground: Color(0x1FFFFFFF),
    focusGlow: [],
  ),
);
