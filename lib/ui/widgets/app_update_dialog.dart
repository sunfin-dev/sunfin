import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/app_update_installer.dart';
import '../../data/services/app_update_service.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';
import 'track_selector_dialog.dart';

/// Checks for an update and shows the dialog or an appropriate snackbar.
Future<void> checkAndShowUpdateResult(BuildContext context) async {
  final result =
      await GetIt.instance<AppUpdateService>().checkForUpdateNowDetailed();
  if (!context.mounted) return;

  final update = result.update;
  if (update != null) {
    await showAppUpdateDialog(context, update);
    return;
  }

  final l10n = AppLocalizations.of(context);
  final message = switch (result.status) {
    DesktopUpdateCheckStatus.upToDate => l10n.youAreUpToDate,
    DesktopUpdateCheckStatus.checkFailed => l10n.couldNotCheckForUpdates,
    DesktopUpdateCheckStatus.unsupportedPlatform => l10n.updateChecksNotSupported,
    DesktopUpdateCheckStatus.managedByStore => l10n.updateChecksNotSupported,
    DesktopUpdateCheckStatus.disabledByPreference => l10n.updateNotificationsDisabled,
    DesktopUpdateCheckStatus.rateLimited => l10n.pleaseWaitBeforeChecking,
    DesktopUpdateCheckStatus.alreadyNotified => l10n.latestUpdateAlreadyShown,
    DesktopUpdateCheckStatus.updateAvailable => l10n.updateAvailable,
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

bool _startupPromptDone = false;

/// Sunfin: once per app start, when the home screen first shows, checks
/// GitHub and offers a newer release. Declining keeps the prompt for that
/// version away for a day; Settings > About can still install it.
Future<void> promptForAppUpdateAtStartup(BuildContext context) async {
  if (_startupPromptDone) return;
  _startupPromptDone = true;
  DesktopUpdateInfo? update;
  try {
    update = await GetIt.instance<AppUpdateService>().checkForUpdateIfDue();
  } catch (_) {
    return;
  }
  if (update == null || !context.mounted) return;
  // Something opened on top in the meantime (a player, a dialog): don't cut in.
  if (ModalRoute.of(context)?.isCurrent == false) return;
  await showAppUpdateDialog(context, update);
}

Future<void> showAppUpdateDialog(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);
  final canInstall = update.installable && AppUpdateInstaller.supported;

  final choice = await showStyledPlayerDialog<String>(
    context,
    title: l10n.updateAvailableTitle(update.version),
    showCancel: true,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canInstall)
          _UpdateOption(
            icon: Icons.system_update_alt_rounded,
            label: l10n.install,
            value: 'install',
            autofocus: true,
          )
        else if (!PlatformDetection.isTV)
          _UpdateOption(
            icon: Icons.download_rounded,
            label: l10n.download,
            value: 'download',
            autofocus: true,
          ),
        _UpdateOption(
          icon: Icons.article_outlined,
          label: l10n.readReleaseNotes,
          value: 'notes',
          autofocus: !canInstall && PlatformDetection.isTV,
        ),
      ],
    ),
  );

  if (choice == null || !context.mounted) return;

  if (choice == 'install') {
    await installAppUpdate(context, update);
    return;
  }

  final uri =
      choice == 'notes' ? Uri.parse(update.releaseNotesUrl) : update.downloadUri;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Downloads and installs [update] behind a progress dialog. On Android the
/// dialog closes once the system installer is open; on Windows Sunfin exits
/// and restarts updated. A Windows folder Sunfin can't write to sends the user
/// to the release page instead.
Future<void> installAppUpdate(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progressNotifier = ValueNotifier<double>(0.0);
  final errorNotifier = ValueNotifier<String?>(null);

  unawaited(showStyledPlayerDialog<void>(
    context,
    title: l10n.updating,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: AnimatedBuilder(
          animation: Listenable.merge([progressNotifier, errorNotifier]),
          builder: (context, child) {
            final error = errorNotifier.value;
            if (error != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: TextButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        l10n.close,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            }

            final progress = progressNotifier.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            );
          },
        ),
      ),
    ),
  ));

  try {
    await AppUpdateInstaller.install(
      update,
      onProgress: (value) => progressNotifier.value = value,
    );
    if (navigator.mounted) navigator.pop();
  } on AppUpdateException catch (e) {
    debugPrint('In-app update failed: $e');
    if (e.failure == AppUpdateFailure.folderNotWritable) {
      if (navigator.mounted) navigator.pop();
      await launchUrl(
        Uri.parse(update.releaseNotesUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    errorNotifier.value = l10n.updateDownloadFailed;
  } catch (e) {
    debugPrint('In-app update failed: $e');
    errorNotifier.value = l10n.updateDownloadFailed;
  }
}

// Sunfin: drawn like the track picker's rows, so keyboard and remote focus
// shows (upstream's InkWell had no visible focus state here).
class _UpdateOption extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool autofocus;

  const _UpdateOption({
    required this.icon,
    required this.label,
    required this.value,
    this.autofocus = false,
  });

  @override
  State<_UpdateOption> createState() => _UpdateOptionState();
}

class _UpdateOptionState extends State<_UpdateOption> {
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(
      () => setState(() => _isFocused = _focusNode.hasFocus),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _choose() => Navigator.of(context).pop(widget.value);

  @override
  Widget build(BuildContext context) {
    final focusColor = Color(
      GetIt.instance<UserPreferences>().get(UserPreferences.focusColor).colorValue,
    );
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _choose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _choose,
        child: Container(
          width: double.infinity,
          color: _isFocused
              ? focusColor.withValues(alpha: 0.2)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 22,
                color: _isFocused ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 16),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: _isFocused ? 1 : 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
