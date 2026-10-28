import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import 'providers/admin_websocket_handler.dart';
import 'widgets/admin_drawer.dart';
import 'widgets/admin_look.dart';

class AdminShellScreen extends StatelessWidget {
  final Widget child;

  /// The admin area's own navigator, so its stack can be told apart from the
  /// root one, which also holds the home screen the whole area was pushed over.
  static final navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'admin');

  const AdminShellScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = AdminLook.theme(Theme.of(context));
    final width = MediaQuery.sizeOf(context).width;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final isCompact = width < 430;
    final currentPath = GoRouterState.of(context).uri.path;
    // A screen pushed inside the area pops back to the one that opened it.
    // Sections picked from the drawer or sidebar replace the stack instead, so
    // they get the menu, or nothing beside the embedded sidebar. The depth
    // comes from the router rather than the navigator, which is a child of
    // this widget and still holds the previous stack while this builds.
    final canGoBack = _stackDepth(context) > 1;
    const backdrop = BoxDecoration(color: AdminLook.page);
    // Admin pages draw no background of their own, so each one carries what
    // sits behind it. Otherwise the page being left stays readable under the
    // one fading in.
    final pages = Theme(
      data: theme.copyWith(
        pageTransitionsTheme: _BackedPageTransitions(
          theme.pageTransitionsTheme,
          backdrop: backdrop,
        ),
      ),
      child: child,
    );

    return Theme(
      data: theme,
      child: AdminWebSocketHandler(
        child: Scaffold(
          appBar: AppBar(
            // The area sits over the home screen, so an empty slot would get
            // an implied arrow that leaves it, which is what the close button
            // is for.
            automaticallyImplyLeading: false,
            shape: const Border(bottom: BorderSide(color: AdminLook.line)),
            toolbarHeight: isCompact ? kToolbarHeight : 56,
            leading: canGoBack
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: context.pop,
                  )
                : isWide
                ? null
                : Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
            titleSpacing: 20,
            title: Text(
              l10n.adminServerAdministrationTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (isCompact
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(fontWeight: FontWeight.w500),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                color: AdminLook.muted,
                tooltip: l10n.adminExitTooltip,
                onPressed: () => context.go(Destinations.home),
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: isWide ? null : AdminDrawer(currentPath: currentPath),
          body: DecoratedBox(
            decoration: backdrop,
            child: isWide
                ? Row(
                    children: [
                      Container(
                        width: 250,
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: AdminLook.line),
                          ),
                        ),
                        child: AdminDrawer(
                          currentPath: currentPath,
                          isEmbedded: true,
                        ),
                      ),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: const _AdminShellScrollBehavior(),
                          child: pages,
                        ),
                      ),
                    ],
                  )
                : pages,
          ),
        ),
      ),
    );
  }

  static int _stackDepth(BuildContext context) {
    final configuration = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration;
    for (final match in configuration.matches) {
      if (match is ShellRouteMatch && match.navigatorKey == navigatorKey) {
        return match.matches.length;
      }
    }
    return 0;
  }
}

class _BackedPageTransitions extends PageTransitionsTheme {
  _BackedPageTransitions(this._base, {required this.backdrop})
    : super(builders: _base.builders);

  final PageTransitionsTheme _base;
  final Decoration backdrop;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _base.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    DecoratedBox(decoration: backdrop, child: child),
  );
}

class _AdminShellScrollBehavior extends MaterialScrollBehavior {
  const _AdminShellScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
