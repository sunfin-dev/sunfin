import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a socket with [headers] on the upgrade request.
WebSocketChannel connectServerSocket(Uri uri, Map<String, String> headers) {
  return IOWebSocketChannel.connect(uri, headers: headers);
}
