import 'package:flutter/material.dart';

import '../../../widgets/bottom_nav/bottom_navbar.dart';
import 'shared/nouveau_spacing.dart';

class NouveauLandscapeLayout extends StatelessWidget {
  final Widget backdrop;
  final Widget hero;

  /// Positioned widgets laid over the top of the hero, scrolling with it.
  final List<Widget> heroOverlays;
  final List<Widget> sections;
  final ScrollController scrollController;

  final EdgeInsetsGeometry heroPadding;
  final EdgeInsetsGeometry firstSectionPadding;
  final EdgeInsetsGeometry remainingSectionsPadding;

  final bool compactFirstFold;
  final double compactHeroHeight;
  final double compactHeroToSectionSpacing;

  const NouveauLandscapeLayout({
    super.key,
    required this.backdrop,
    required this.hero,
    this.heroOverlays = const [],
    required this.sections,
    required this.scrollController,
    this.heroPadding = EdgeInsets.zero,
    this.firstSectionPadding = const EdgeInsets.fromLTRB(56, 0, 56, 0),
    this.remainingSectionsPadding = const EdgeInsets.fromLTRB(56, 0, 56, 0),
    this.compactFirstFold = false,
    this.compactHeroHeight = 370,
    this.compactHeroToSectionSpacing = 20,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final firstSection = sections.isNotEmpty
        ? sections.first
        : const SizedBox.shrink();

    final remainingSections = sections.length > 1
        ? sections.skip(1).toList(growable: false)
        : const <Widget>[];

    final resolvedHeroPadding = heroPadding.resolve(Directionality.of(context));

    final nonCompactHeroPadding = EdgeInsets.only(
      top: resolvedHeroPadding.top,
      left: resolvedHeroPadding.left,
      right: resolvedHeroPadding.right,
    );

    final compactHeroFrameHeight =
        compactHeroHeight + resolvedHeroPadding.vertical;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: backdrop),

        CustomScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            if (compactFirstFold) ...[
              SliverToBoxAdapter(
                child: _withHeroOverlays(
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: size.height),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: compactHeroFrameHeight,
                          child: Padding(padding: heroPadding, child: hero),
                        ),

                        if (compactHeroToSectionSpacing > 0)
                          SizedBox(height: compactHeroToSectionSpacing),

                        Padding(
                          padding: firstSectionPadding,
                          child: firstSection,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (remainingSections.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: remainingSectionsPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: remainingSections,
                    ),
                  ),
                ),
            ] else ...[
              SliverToBoxAdapter(
                child: _withHeroOverlays(
                  Padding(padding: nonCompactHeroPadding, child: hero),
                ),
              ),

              if (sections.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: NouveauSpacing.sectionGap),

                      Padding(
                        padding: firstSectionPadding,
                        child: firstSection,
                      ),

                      if (remainingSections.isNotEmpty)
                        Padding(
                          padding: remainingSectionsPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: remainingSections,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: bottomContentInset(context)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _withHeroOverlays(Widget child) {
    if (heroOverlays.isEmpty) return child;
    return Stack(children: [child, ...heroOverlays]);
  }
}
