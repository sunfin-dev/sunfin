import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import '../../util/app_exit.dart';
import '../../util/focus/key_event_utils.dart';
import '../sunfin/sunfin_style.dart';
import 'navigation_layout.dart';
import 'overlay_sheet.dart';

bool _exitDialogVisible = false;

Future<void> showExitConfirmationDialog(BuildContext context) async {
  if (_exitDialogVisible) return;
  _exitDialogVisible = true;
  final l10n = AppLocalizations.of(context);
  final cancelFocus = FocusNode(debugLabel: 'ExitDialogCancel');
  try {
    final result = await OverlaySheetController.show<bool>(
      context,
      initialFocusNode: cancelFocus,
      builder: (sheetContext) => _ExitConfirmationContent(
        title: l10n.exitApp,
        message: l10n.exitAppConfirmation,
        cancelLabel: l10n.cancel,
        exitLabel: l10n.exit,
        cancelFocus: cancelFocus,
        onCancel: () => OverlaySheetController.closeAdaptive<bool>(
          sheetContext,
          result: false,
        ),
        onExit: () => OverlaySheetController.closeAdaptive<bool>(
          sheetContext,
          result: true,
        ),
      ),
    );
    if (result == true) {
      await AppExit.closeApp();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusAvatar = NavigationLayout.focusNavbarAvatarNotifier.value;
        if (focusAvatar != null) {
          focusAvatar();
          return;
        }
        NavigationLayout.focusNavbarNotifier.value?.call();
      });
    }
  } finally {
    _exitDialogVisible = false;
    cancelFocus.dispose();
  }
}

class _ExitConfirmationContent extends StatefulWidget {
  final String title;
  final String message;
  final String cancelLabel;
  final String exitLabel;
  final FocusNode cancelFocus;
  final VoidCallback onCancel;
  final VoidCallback onExit;

  const _ExitConfirmationContent({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.exitLabel,
    required this.cancelFocus,
    required this.onCancel,
    required this.onExit,
  });

  @override
  State<_ExitConfirmationContent> createState() =>
      _ExitConfirmationContentState();
}

class _ExitConfirmationContentState extends State<_ExitConfirmationContent> {
  final _exitFocus = FocusNode(debugLabel: 'ExitDialogExit');

  @override
  void dispose() {
    _exitFocus.dispose();
    super.dispose();
  }

  /// The title with "fin" of the app name in Sunfin gold, as in the wordmark.
  /// Languages that don't name the app keep the plain title.
  Widget _title() {
    const style = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      decoration: TextDecoration.none,
    );
    final title = widget.title;
    final at = title.indexOf(_appName);
    if (at < 0) return Text(title, style: style, textAlign: TextAlign.center);
    final finAt = at + _appName.length - 3;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: title.substring(0, finAt)),
          const TextSpan(
            text: 'fin',
            style: TextStyle(color: SunfinStyle.accent),
          ),
          TextSpan(text: title.substring(finAt + 3)),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  static const _appName = 'Sunfin';

  /// Sunfin's exit card: the fin mark, a thin
  /// gold top edge, and gold pill buttons.
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 46,
              offset: Offset(0, 17),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.circular(10),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2B2F32), Color(0xFF232628)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ColoredBox(
                  color: SunfinStyle.accent,
                  child: SizedBox(height: 3),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(34, 32, 34, 34),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/moonfin_logo.svg',
                        width: 62,
                        height: 62,
                      ),
                      const SizedBox(height: 14),
                      _title(),
                      const SizedBox(height: 9),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.7),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ExitDialogButton(
                            label: widget.cancelLabel,
                            focusNode: widget.cancelFocus,
                            autofocus: true,
                            onPressed: widget.onCancel,
                          ),
                          const SizedBox(width: 14),
                          _ExitDialogButton(
                            label: widget.exitLabel,
                            focusNode: _exitFocus,
                            onPressed: widget.onExit,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitDialogButton extends StatefulWidget {
  final String label;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool autofocus;

  const _ExitDialogButton({
    required this.label,
    required this.focusNode,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_ExitDialogButton> createState() => _ExitDialogButtonState();
}

class _ExitDialogButtonState extends State<_ExitDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) => handleOneShotSelect(event, widget.onPressed),
      child: GestureDetector(
        onTap: widget.onPressed,
        // The reference design's Play/Resume pill: gold with dark text when focused.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 11),
          decoration: BoxDecoration(
            color: _focused
                ? SunfinStyle.accent
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: _focused ? const Color(0xFF1F1F1F) : Colors.white,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
