import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../preference/user_preferences.dart';
import '../../../navigation/destinations.dart';
import '../../../sunfin/sunfin_style.dart';
import 'admin_look.dart';

class AdminDrawer extends StatefulWidget {
  final String currentPath;
  final bool isEmbedded;

  const AdminDrawer({
    super.key,
    required this.currentPath,
    this.isEmbedded = false,
  });

  @override
  State<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<AdminDrawer> {
  final _prefs = GetIt.instance<UserPreferences>();
  List<_AdminNavEntry> _entries = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    final saved = _prefs.get(UserPreferences.adminDrawerOrder);
    _entries = _orderedEntries(_buildDefaultEntries(l10n), saved);
  }

  List<_AdminNavEntry> _orderedEntries(
    List<_AdminNavEntry> defaults,
    String savedOrder,
  ) {
    if (savedOrder.isEmpty) {
      return List<_AdminNavEntry>.from(defaults);
    }

    final byId = <String, _AdminNavEntry>{for (final e in defaults) e.id: e};
    final ordered = <_AdminNavEntry>[];
    final seen = <String>{};

    for (final id in savedOrder.split(',')) {
      final trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      final entry = byId[trimmed];
      if (entry == null || seen.contains(trimmed)) continue;
      ordered.add(entry);
      seen.add(trimmed);
    }

    for (final entry in defaults) {
      if (!seen.contains(entry.id)) {
        ordered.add(entry);
      }
    }

    return ordered;
  }

  void _saveOrder() {
    final value = _entries.map((e) => e.id).join(',');
    _prefs.set(UserPreferences.adminDrawerOrder, value);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final moved = _entries.removeAt(oldIndex);
      _entries.insert(newIndex, moved);
    });
    _saveOrder();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = widget.isEmbedded
        ? mediaQuery.padding.bottom + 16
        : mediaQuery.padding.bottom + 88;

    final content = SafeArea(
      bottom: true,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: EdgeInsets.only(bottom: bottomPadding),
        itemCount: _entries.length,
        onReorder: _onReorder,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final previousSection = index > 0
              ? _entries[index - 1].section
              : null;
          final showSection = index == 0 || previousSection != entry.section;
          return Column(
            key: ValueKey('admin-drawer-${entry.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isEmbedded && index == 0) const SizedBox(height: 8),
              if (showSection) _section(context, entry.section),
              _tile(context, entry, index),
            ],
          );
        },
      ),
    );

    if (widget.isEmbedded) return content;
    return Drawer(child: content);
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 6),
      child: Text(title.toUpperCase(), style: AdminLook.sectionStyle),
    );
  }

  /// A plain row; the open page sits in Sunfin's white pill. Dragging a
  /// row after a long press still reorders the menu.
  Widget _tile(BuildContext context, _AdminNavEntry entry, int index) {
    final theme = Theme.of(context);
    final selected = widget.currentPath == entry.destination;
    final color = selected ? AdminLook.onPill : const Color(0xFFD8D8D8);
    return ReorderableDelayedDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: Material(
          color: selected ? AdminLook.pill : Colors.transparent,
          borderRadius: AdminLook.borderRadius,
          child: InkWell(
            borderRadius: AdminLook.borderRadius,
            onTap: () {
              if (!widget.isEmbedded) {
                Navigator.of(context).pop();
              }
              if (!selected) {
                context.go(entry.destination);
              }
            },
            child: SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      entry.icon,
                      size: 19,
                      weight: sunfinIconWeight,
                      color: color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminNavEntry {
  final String id;
  final String section;
  final String title;
  final IconData icon;
  final String destination;

  const _AdminNavEntry({
    required this.id,
    required this.section,
    required this.title,
    required this.icon,
    required this.destination,
  });
}

List<_AdminNavEntry> _buildDefaultEntries(AppLocalizations l10n) => [
  _AdminNavEntry(
    id: 'dashboard',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerDashboard,
    icon: Symbols.dashboard,
    destination: Destinations.admin,
  ),
  _AdminNavEntry(
    id: 'analytics',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerAnalytics,
    icon: Symbols.insights,
    destination: Destinations.adminAnalytics,
  ),
  _AdminNavEntry(
    id: 'settings',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerSettings,
    icon: Symbols.settings,
    destination: Destinations.adminSettings,
  ),
  _AdminNavEntry(
    id: 'branding',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerBranding,
    icon: Symbols.brush,
    destination: Destinations.adminSettingsBranding,
  ),
  _AdminNavEntry(
    id: 'users',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerUsers,
    icon: Symbols.group,
    destination: Destinations.adminUsers,
  ),
  _AdminNavEntry(
    id: 'libraries',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerLibraries,
    icon: Symbols.video_library,
    destination: Destinations.adminLibraries,
  ),
  _AdminNavEntry(
    id: 'display',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerDisplay,
    icon: Symbols.grid_view,
    destination: Destinations.adminSettingsDisplay,
  ),
  _AdminNavEntry(
    id: 'metadata',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerMetadata,
    icon: Symbols.description,
    destination: Destinations.adminSettingsMetadata,
  ),
  _AdminNavEntry(
    id: 'nfo',
    section: l10n.adminDrawerSectionServer,
    title: l10n.adminDrawerNfo,
    icon: Symbols.text_snippet,
    destination: Destinations.adminSettingsNfo,
  ),
  _AdminNavEntry(
    id: 'transcoding',
    section: l10n.adminDrawerSectionPlayback,
    title: l10n.adminDrawerTranscoding,
    icon: Symbols.swap_horiz,
    destination: Destinations.adminSettingsPlayback,
  ),
  _AdminNavEntry(
    id: 'resume',
    section: l10n.adminDrawerSectionPlayback,
    title: l10n.adminDrawerResume,
    icon: Symbols.play_circle,
    destination: Destinations.adminSettingsResume,
  ),
  _AdminNavEntry(
    id: 'streaming',
    section: l10n.adminDrawerSectionPlayback,
    title: l10n.adminDrawerStreaming,
    icon: Symbols.stream,
    destination: Destinations.adminSettingsStreaming,
  ),
  _AdminNavEntry(
    id: 'trickplay',
    section: l10n.adminDrawerSectionPlayback,
    title: l10n.adminDrawerTrickplay,
    icon: Symbols.view_comfy,
    destination: Destinations.adminSettingsTrickplay,
  ),
  _AdminNavEntry(
    id: 'devices',
    section: l10n.adminDrawerSectionDevices,
    title: l10n.adminDrawerDevices,
    icon: Symbols.devices,
    destination: Destinations.adminDevices,
  ),
  _AdminNavEntry(
    id: 'activity',
    section: l10n.adminDrawerSectionDevices,
    title: l10n.adminDrawerActivity,
    icon: Symbols.history,
    destination: Destinations.adminActivity,
  ),
  _AdminNavEntry(
    id: 'networking',
    section: l10n.adminDrawerSectionAdvanced,
    title: l10n.adminDrawerNetworking,
    icon: Symbols.language,
    destination: Destinations.adminSettingsNetworking,
  ),
  _AdminNavEntry(
    id: 'api-keys',
    section: l10n.adminDrawerSectionAdvanced,
    title: l10n.adminDrawerApiKeys,
    icon: Symbols.vpn_key,
    destination: Destinations.adminKeys,
  ),
  _AdminNavEntry(
    id: 'backups',
    section: l10n.adminDrawerSectionAdvanced,
    title: l10n.adminDrawerBackups,
    icon: Symbols.backup,
    destination: Destinations.adminBackups,
  ),
  _AdminNavEntry(
    id: 'logs',
    section: l10n.adminDrawerSectionAdvanced,
    title: l10n.adminDrawerLogs,
    icon: Symbols.article,
    destination: Destinations.adminLogs,
  ),
  _AdminNavEntry(
    id: 'scheduled-tasks',
    section: l10n.adminDrawerSectionAdvanced,
    title: l10n.adminDrawerScheduledTasks,
    icon: Symbols.schedule,
    destination: Destinations.adminTasks,
  ),
  _AdminNavEntry(
    id: 'plugins',
    section: l10n.adminDrawerSectionPlugins,
    title: l10n.adminDrawerPlugins,
    icon: Symbols.extension,
    destination: Destinations.adminPlugins,
  ),
  _AdminNavEntry(
    id: 'repositories',
    section: l10n.adminDrawerSectionPlugins,
    title: l10n.adminDrawerRepositories,
    icon: Symbols.source,
    destination: Destinations.adminRepositories,
  ),
  _AdminNavEntry(
    id: 'live-tv',
    section: l10n.adminDrawerSectionLiveTv,
    title: l10n.adminDrawerLiveTv,
    icon: Symbols.live_tv,
    destination: Destinations.adminLiveTv,
  ),
];
