import 'package:flutter/material.dart';

import '../widgets/navigation_layout.dart';
import 'sunfin_style.dart';

/// Sunfin mode: gives a full-screen browse page (library grids, music, genres,
/// favorites) the left rail, as the reference app shows it on every section.
/// Upstream these pages have no navigation chrome, so outside Sunfin mode the
/// page comes back untouched.
///
/// The rail is solid and the page sits to its right (navigation_layout.dart),
/// so the page needs no inset of its own for it.
Widget sunfinNavShell({required Widget child, Color? background}) {
  if (!SunfinStyle.enabled) return child;
  return Scaffold(
    backgroundColor: background ?? SunfinStyle.background,
    body: NavigationLayout(child: child),
  );
}

/// Side margin of a browse page. Upstream's TV margin partly sat under the
/// overlaid rail; beside the solid rail it would double up, so Sunfin mode uses
/// the shared content inset instead.
double sunfinBrowseMargin(double upstream) =>
    SunfinStyle.enabled ? SunfinStyle.contentInset : upstream;

/// For widgets that hold left at the start of a row instead of letting focus
/// wander: in Sunfin mode that press opens the rail. Says whether it did, so
/// the caller can keep its upstream handling otherwise.
bool sunfinFocusRailFromEdge() {
  if (!SunfinStyle.enabled) return false;
  return NavigationLayout.focusNavbar();
}
