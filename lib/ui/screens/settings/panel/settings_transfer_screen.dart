part of '../settings_side_panel.dart';

/// Sunfin: moves every setting from one device to another through the
/// user's Jellyfin account (SettingsTransfer). The other device signs in on
/// its own first; logins never travel.
class _SettingsTransferScreen extends StatefulWidget {
  const _SettingsTransferScreen();

  @override
  State<_SettingsTransferScreen> createState() =>
      _SettingsTransferScreenState();
}

class _SettingsTransferScreenState extends State<_SettingsTransferScreen> {
  DisplayPreferencesApi get _api =>
      GetIt.instance<MediaServerClient>().displayPreferencesApi;

  /// What the account holds: null while loading, empty when nothing was
  /// exported yet.
  Map<String, Object?>? _stored;
  bool _loadFailed = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stored = await SettingsTransfer.fetch(_api);
      if (!mounted) return;
      setState(() {
        _stored = stored ?? const {};
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('Settings transfer: reading the account failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  static String get _deviceName {
    if (PlatformDetection.isAndroid) {
      return PlatformDetection.isTV ? 'Android TV' : 'Android';
    }
    if (PlatformDetection.isWindows) return 'Windows';
    if (PlatformDetection.isMacOS) return 'macOS';
    if (PlatformDetection.isLinux) return 'Linux';
    if (PlatformDetection.isAppleTV) return 'Apple TV';
    if (PlatformDetection.isIOS) return 'iOS';
    return 'Web';
  }

  String? _describe(Map<String, Object?> stored) {
    if (stored.isEmpty) return null;
    final when = DateTime.tryParse('${stored['exportedAt']}')?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = when == null
        ? ''
        : '${localizations.formatMediumDate(when)} '
              '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(when))}';
    return AppLocalizations.of(context)
        .settingsTransferFrom('${stored['device']}', date);
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    String message;
    try {
      final count = await SettingsTransfer.export(_api, device: _deviceName);
      // Read it back: offline, the save is dropped without an error.
      final stored = await SettingsTransfer.fetch(_api);
      if (stored == null) throw StateError('not saved');
      _stored = stored;
      message = l10n.settingsTransferExported(count);
    } catch (e) {
      debugPrint('Settings transfer: export failed: $e');
      message = l10n.settingsTransferFailed;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
      });
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final stored = _stored;
    if (stored == null || stored.isEmpty) return;
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.settingsTransferImport),
        content: Text(
          l10n.settingsTransferImportConfirm(_describe(stored) ?? ''),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.settingsTransferImportAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // The newest snapshot, in case another device exported meanwhile.
      final latest = await SettingsTransfer.fetch(_api) ?? stored;
      final prefs = await SharedPreferences.getInstance();
      await SettingsTransfer.apply(prefs, latest);
      await GetIt.instance<PreferenceStore>().flushPendingWrites();
    } catch (e) {
      debugPrint('Settings transfer: import failed: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _message = l10n.settingsTransferFailed;
        });
      }
      return;
    }
    // Much of the app reads its settings once at start, so it starts again
    // rather than run half on the old ones.
    exit(0);
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.settingsReset),
        content: Text(l10n.settingsResetConfirm),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.reset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    // A write still in flight would land after the reset and bring its
    // setting back.
    await GetIt.instance<PreferenceStore>().flushPendingWrites();
    await SettingsTransfer.reset(await SharedPreferences.getInstance());
    // As after an import: start again on the defaults.
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stored = _stored;
    final described = stored == null ? null : _describe(stored);
    final canImport = !_busy && described != null;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, Text(l10n.settingsTransfer)),
        body: ListView(
          children: [
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  autofocus: true,
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(l10n.settingsTransferExport),
                  subtitle: Text(l10n.settingsTransferExportSubtitle),
                  onTap: _busy ? null : _export,
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(l10n.settingsTransferImport),
                  subtitle: Text(
                    _loadFailed
                        ? l10n.settingsTransferFailed
                        : stored == null
                        ? '…'
                        : described ?? l10n.settingsTransferNothing,
                  ),
                  onTap: canImport ? _import : null,
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: Text(l10n.settingsReset),
                  subtitle: Text(l10n.settingsResetSubtitle),
                  onTap: _busy ? null : _reset,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                _message ?? l10n.settingsTransferNote,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
