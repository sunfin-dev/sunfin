import 'package:web_socket_channel/web_socket_channel.dart';

/// Browsers give a socket no way to send headers, so [headers] are dropped and
/// the server falls back to what it stored for the token.
WebSocketChannel connectServerSocket(Uri uri, Map<String, String> headers) {
  return WebSocketChannel.connect(uri);
}
