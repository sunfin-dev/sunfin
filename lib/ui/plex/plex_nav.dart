import 'package:flutter/material.dart';

import '../widgets/navigation_layout.dart';
import 'plex_style.dart';

/// Plex mode: gives a full-screen browse page (library grids, music, genres,
/// favorites) the left rail, as the Plex app shows it on every section.
/// Upstream these pages have no navigation chrome, so outside Plex mode the
/// page comes back untouched.
///
/// The rail is solid and the page sits to its right (navigation_layout.dart),
/// so the page needs no inset of its own for it.
Widget plexNavShell({required Widget child, Color? background}) {
  if (!PlexStyle.enabled) return child;
  return Scaffold(
    backgroundColor: background ?? PlexStyle.background,
    body: NavigationLayout(child: child),
  );
}

/// Side margin of a browse page. Upstream's TV margin partly sat under the
/// overlaid rail; beside the solid rail it would double up, so Plex mode uses
/// the shared content inset instead.
double plexBrowseMargin(double upstream) =>
    PlexStyle.enabled ? PlexStyle.contentInset : upstream;

/// For widgets that hold left at the start of a row instead of letting focus
/// wander: in Plex mode that press opens the rail. Says whether it did, so
/// the caller can keep its upstream handling otherwise.
bool plexFocusRailFromEdge() {
  if (!PlexStyle.enabled) return false;
  return NavigationLayout.focusNavbar();
}
