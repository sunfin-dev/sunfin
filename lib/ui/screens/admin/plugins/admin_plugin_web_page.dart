import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../util/platform_detection.dart';
import '../../../../util/webview_environment.dart';
import '../widgets/admin_look.dart';

/// Whether a plugin's settings page can open inside the app. The web view
/// has no Linux or web build; there it opens in the browser.
bool get adminPluginWebPageSupported =>
    !PlatformDetection.isWeb && !PlatformDetection.isLinux;

/// Opens [uri], a plugin's settings page in the server's own web client,
/// over the whole window.
Future<void> openAdminPluginWebPage(
  BuildContext context, {
  required String title,
  required Uri uri,
}) {
  final theme = AdminLook.theme(Theme.of(context));
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: theme,
        child: AdminPluginWebPage(title: title, uri: uri),
      ),
    ),
  );
}

/// A plugin's settings page, which plugins write as part of the server's web
/// client. The web client signs in by its own session the first time
/// (Quick Connect or password) and the web view keeps it, so the app's own
/// sign-in is never handed over.
class AdminPluginWebPage extends StatefulWidget {
  final String title;
  final Uri uri;

  const AdminPluginWebPage({super.key, required this.title, required this.uri});

  @override
  State<AdminPluginWebPage> createState() => _AdminPluginWebPageState();
}

class _AdminPluginWebPageState extends State<AdminPluginWebPage> {
  InAppWebViewController? _controller;
  double _progress = 0;

  /// Set once the web client asked to sign in; it lands on its home page
  /// afterwards, and the plugin page is opened again from there.
  bool _signingIn = false;

  void _onUrlChanged(WebUri? url) {
    final route = url?.fragment ?? '';
    if (route.startsWith('/login') || route.startsWith('/selectserver')) {
      _signingIn = true;
      return;
    }
    if (_signingIn && route.startsWith('/home')) {
      _signingIn = false;
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(widget.uri)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        shape: const Border(bottom: BorderSide(color: AdminLook.line)),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            color: AdminLook.muted,
            tooltip: l10n.refresh,
            onPressed: () => _controller?.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            color: AdminLook.muted,
            tooltip: l10n.adminOpenInBrowser,
            onPressed: () =>
                launchUrl(widget.uri, mode: LaunchMode.externalApplication),
          ),
          const SizedBox(width: 8),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: InAppWebView(
        webViewEnvironment: gWebViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri.uri(widget.uri)),
        initialSettings: InAppWebViewSettings(
          isInspectable: false,
          mediaPlaybackRequiresUserGesture: true,
        ),
        onWebViewCreated: (controller) => _controller = controller,
        onProgressChanged: (_, progress) {
          if (mounted) setState(() => _progress = progress / 100);
        },
        onUpdateVisitedHistory: (_, url, _) => _onUrlChanged(url),
      ),
    );
  }
}
