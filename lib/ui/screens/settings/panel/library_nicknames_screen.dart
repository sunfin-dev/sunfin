part of '../settings_side_panel.dart';

/// Plexfin: the user's own names for their libraries, shown everywhere in the
/// app and never written to the server (LibraryNicknames).
class _LibraryNicknamesScreen extends StatefulWidget {
  const _LibraryNicknamesScreen();

  @override
  State<_LibraryNicknamesScreen> createState() =>
      _LibraryNicknamesScreenState();
}

class _LibraryNicknamesScreenState extends State<_LibraryNicknamesScreen> {
  final _viewsRepo = GetIt.instance<UserViewsRepository>();
  List<AggregatedLibrary>? _libraries;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final libraries = await _viewsRepo.getAllViewsIncludingHidden();
      if (!mounted) return;
      setState(() {
        _libraries = libraries;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  /// The library's name on the server: kept with its nickname once it has
  /// one, since the list then shows the nickname.
  String _serverName(AggregatedLibrary library) =>
      LibraryNicknames.serverNameFor(library.id) ?? library.name;

  Future<void> _edit(AggregatedLibrary library) async {
    final l10n = AppLocalizations.of(context);
    final serverName = _serverName(library);
    final controller = TextEditingController(
      text: LibraryNicknames.nicknameFor(library.id) ?? '',
    );
    final next = await showFocusRestoringDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(serverName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.libraryNicknameHint),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) return;
    await LibraryNicknames.set(
      library.id,
      nickname: next,
      serverName: serverName,
    );
    // The sidebar and home read the libraries again, now with the new name.
    _viewsRepo.viewsChanged();
    homeRefreshBus.requestNowOrAfterNavigation();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final libraries = _libraries;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, Text(l10n.libraryNicknames)),
        body: libraries == null
            ? Center(
                child: _loadFailed
                    ? Text(l10n.libraryNicknamesLoadFailed)
                    : const CircularProgressIndicator(),
              )
            : ListView(
                children: [
                  adaptiveListSection(
                    children: [
                      for (final (i, library) in libraries.indexed)
                        _TvSettingsListTile(
                          autofocus: i == 0,
                          leading: const Icon(Icons.drive_file_rename_outline),
                          title: Text(
                            LibraryNicknames.nicknameFor(library.id) ??
                                _serverName(library),
                          ),
                          subtitle: Text(
                            LibraryNicknames.nicknameFor(library.id) == null
                                ? l10n.libraryNicknameNone
                                : l10n.libraryNicknameServerName(
                                    _serverName(library),
                                  ),
                          ),
                          onTap: () => _edit(library),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
