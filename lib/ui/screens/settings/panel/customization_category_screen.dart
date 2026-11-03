part of '../settings_side_panel.dart';

class _CustomizationCategoryScreen extends StatelessWidget {
  const _CustomizationCategoryScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Sunfin: the subtitles name only what the locked look leaves to change.
    final sunfin = SunfinLocks.active;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(
          context,
          Text(l10n.settingsPersonalization),
        ),
        body: ListView(
          children: [
            _SectionHeader(l10n.appearance),
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  autofocus: true,
                  leading: const Icon(Icons.style),
                  title: Text(l10n.settingsGeneralStyle),
                  subtitle: Text(
                    sunfin
                        ? l10n.sunfinGeneralStyleSubtitle
                        : l10n.settingsGeneralStyleSubtitle,
                  ),
                  onTap: () =>
                      context.pushSettingsScreen(const _GeneralStyleScreen()),
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(l10n.settingsDetailsScreen),
                  subtitle: Text(
                    sunfin
                        ? l10n.sunfinDetailsScreenSubtitle
                        : l10n.settingsDetailsScreenSubtitle,
                  ),
                  onTap: () => context.pushSettingsScreen(
                    const _DetailsScreenSettingsScreen(),
                  ),
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.view_sidebar),
                  title: Text(l10n.navigation),
                  subtitle: Text(
                    sunfin
                        ? l10n.sunfinNavigationSubtitle
                        : l10n.navbarStyleToolbarAppearance,
                  ),
                  onTap: () => context.pushSettingsScreen(
                    const _NavigationCategoryScreen(),
                  ),
                ),
                if (PlatformDetection.isTV)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.wallpaper),
                    title: Text(l10n.screensaver),
                    subtitle: Text(l10n.enableBuiltInScreensaver),
                    onTap: () => context.pushSettingsScreen(
                      const ScreensaverSettingsScreen(),
                    ),
                  ),
              ],
            ),
            _SectionHeader(l10n.layout),
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  leading: const Icon(Icons.home),
                  title: Text(l10n.homeScreen),
                  subtitle: Text(
                    sunfin
                        ? l10n.sunfinHomeScreenSubtitle
                        : l10n.settingsHomePageSubtitle,
                  ),
                  onTap: () => context.pushSettingsScreen(
                    const _HomeScreenCategoryScreen(),
                  ),
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.video_library),
                  title: Text(l10n.libraries),
                  subtitle: Text(l10n.settingsLibrariesSubtitle),
                  onTap: () => context.pushSettingsScreen(
                    const _LibrariesCategoryScreen(),
                  ),
                ),
              ],
            ),
            _SectionHeader(l10n.extras),
            adaptiveListSection(
              children: [
                // Sunfin: the Sunfin header replaces the media bar, and the
                // loading animation and seasonal effects are part of the
                // fixed look (SunfinLocks).
                if (!SunfinLocks.active) ...[
                  _TvSettingsListTile(
                    leading: const Icon(Icons.featured_play_list),
                    title: Text(l10n.mediaBar),
                    subtitle: Text(l10n.featuredContentAppearance),
                    onTap: () => context.pushSettingsScreen(
                      const MediaBarSettingsScreen(),
                    ),
                  ),
                  _TvSettingsListTile(
                    leading: const Icon(Icons.motion_photos_on_outlined),
                    title: Text(l10n.loadingAnimation),
                    subtitle: Text(l10n.loadingAnimationDescription),
                    onTap: () => context.pushSettingsScreen(
                      const _LoadingAnimationScreen(),
                    ),
                  ),
                ],
                _TvSettingsListTile(
                  leading: const Icon(Icons.preview),
                  title: Text(l10n.localPreviews),
                  subtitle: Text(l10n.localPreviewsDescription),
                  onTap: () => context.pushSettingsScreen(
                    const LocalPreviewsSettingsScreen(),
                  ),
                ),
                if (!SunfinLocks.active)
                  _TvSettingsListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: Text(l10n.seasonalEffects),
                    subtitle: Text(l10n.seasonalEffectsDescription),
                    onTap: () => context.pushSettingsScreen(
                      const _SeasonalEffectsScreen(),
                    ),
                  ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(l10n.themeMusic),
                  subtitle: Text(l10n.themeMusicSettingsSubtitle),
                  onTap: () =>
                      context.pushSettingsScreen(const _ThemeMusicScreen()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _pushPersonalizationSync() {
  final syncService = GetIt.instance<PluginSyncService>();
  if (syncService.pluginAvailable) {
    syncService.pushSettings(GetIt.instance<MediaServerClient>());
  }
}
