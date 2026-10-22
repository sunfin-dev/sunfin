import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../data/services/log_service.dart';

import 'server_discovery_types.dart';

class ServerDiscoveryService {
  static const _discoveryPort = 7359;
  static const _jellyfinMessage = 'who is JellyfinServer?';
  static const _embyMessage = 'who is EmbyServer?';
  static const _listenDuration = Duration(milliseconds: 2500);
  static const _rebroadcastInterval = Duration(milliseconds: 800);

  // Fork: subnet scan for servers that never answer the broadcast, like
  // Jellyfin in a Docker bridge network without 7359/udp published.
  static const _jellyfinHttpPort = 8096;
  static const _scanConnectTimeout = Duration(milliseconds: 700);
  static const _scanConcurrency = 32;

  Stream<DiscoveredServer> discoverLocalServers() async* {
    final controller = StreamController<DiscoveredServer>();
    final seen = <String>{};
    RawDatagramSocket? socket;
    Timer? rebroadcastTimer;
    Timer? stopTimer;
    var listenDone = false;
    var scanDone = false;
    void closeWhenDone() {
      if (listenDone && scanDone && !controller.isClosed) controller.close();
    }

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final broadcastAddresses = await _getBroadcastAddresses();
      final localIps = await _getLocalIpv4Addresses();
      final jellyfinData = utf8.encode(_jellyfinMessage);
      final embyData = utf8.encode(_embyMessage);

      void sendBroadcasts() {
        for (final addr in broadcastAddresses) {
          try {
            socket!.send(jellyfinData, addr, _discoveryPort);
            socket.send(embyData, addr, _discoveryPort);
          } catch (_) {}
        }
      }

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final response = utf8.decode(datagram.data);
        final server = _parseResponse(
          response,
          sender: datagram.address,
          localIps: localIps,
        );
        if (server == null) return;
        if (seen.add(server.id) && !controller.isClosed) {
          controller.add(server);
        }
      });

      sendBroadcasts();
      rebroadcastTimer = Timer.periodic(_rebroadcastInterval, (_) {
        sendBroadcasts();
      });
      stopTimer = Timer(_listenDuration, () {
        listenDone = true;
        rebroadcastTimer?.cancel();
        closeWhenDone();
      });
      unawaited(
        _scanSubnets(localIps, (server) {
          if (seen.add(server.id) && !controller.isClosed) {
            controller.add(server);
          }
        }).whenComplete(() {
          scanDone = true;
          closeWhenDone();
        }),
      );

      yield* controller.stream;
    } catch (error) {
      // Swallowing this leaves an empty list that reads exactly like a
      // network with no servers on it.
      if (GetIt.instance.isRegistered<LogService>()) {
        GetIt.instance<LogService>().network(
          'Local server discovery failed',
          level: LogLevel.error,
          error: error,
        );
      }
      if (!controller.isClosed) await controller.close();
    } finally {
      rebroadcastTimer?.cancel();
      stopTimer?.cancel();
      socket?.close();
      if (!controller.isClosed) await controller.close();
    }
  }

  DiscoveredServer? _parseResponse(
    String response, {
    InternetAddress? sender,
    List<InternetAddress> localIps = const [],
  }) {
    try {
      final data = jsonDecode(response) as Map<String, dynamic>;
      var address = data['Address'] as String?;
      final id = data['Id']?.toString();
      if (address == null || id == null) return null;

      // A server in a container advertises its internal address (e.g.
      // 172.20.0.2), which this device can't reach. Keep scheme and port but
      // use the host the reply actually came from.
      final uri = Uri.tryParse(address);
      final advertised = uri == null ? null : InternetAddress.tryParse(uri.host);
      if (sender != null &&
          uri != null &&
          advertised != null &&
          advertised.address != sender.address &&
          !localIps.any((ip) => _sameSubnet24(ip, advertised))) {
        address = uri.replace(host: sender.address).toString();
      }

      final name = data['Name'] as String? ?? id;

      final serverType = name.toLowerCase().contains('emby')
          ? ServerType.emby
          : ServerType.jellyfin;

      return DiscoveredServer(
        id: id,
        name: name,
        address: address,
        serverType: serverType,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _sameSubnet24(InternetAddress a, InternetAddress b) {
    final pa = a.rawAddress;
    final pb = b.rawAddress;
    return pa.length == 4 &&
        pb.length == 4 &&
        pa[0] == pb[0] &&
        pa[1] == pb[1] &&
        pa[2] == pb[2];
  }

  /// This device's private IPv4 addresses (the networks worth scanning).
  Future<List<InternetAddress>> _getLocalIpv4Addresses() async {
    final result = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final b = addr.rawAddress;
          final private =
              b[0] == 10 ||
              (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
              (b[0] == 192 && b[1] == 168);
          if (private && !addr.isLoopback) result.add(addr);
        }
      }
    } catch (_) {}
    return result;
  }

  /// Asks every host of each local /24 for Jellyfin's public info on the
  /// default port. Only runs on private networks, ~254 short requests each.
  Future<void> _scanSubnets(
    List<InternetAddress> localIps,
    void Function(DiscoveredServer) onFound,
  ) async {
    final hosts = <String>{};
    for (final ip in localIps) {
      final b = ip.rawAddress;
      for (var i = 1; i < 255; i++) {
        final host = '${b[0]}.${b[1]}.${b[2]}.$i';
        if (host != ip.address) hosts.add(host);
      }
    }
    if (hosts.isEmpty) return;

    final client = HttpClient()..connectionTimeout = _scanConnectTimeout;
    final queue = hosts.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final host = queue.removeLast();
        final server = await _probeJellyfin(client, host);
        if (server != null) onFound(server);
      }
    }

    try {
      await Future.wait(List.generate(_scanConcurrency, (_) => worker()));
    } finally {
      client.close(force: true);
    }
  }

  Future<DiscoveredServer?> _probeJellyfin(HttpClient client, String host) async {
    try {
      final request = await client.getUrl(
        Uri.parse('http://$host:$_jellyfinHttpPort/System/Info/Public'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      final data = jsonDecode(body) as Map<String, dynamic>;
      final id = data['Id']?.toString();
      if (id == null || id.isEmpty) return null;
      final product = (data['ProductName'] as String? ?? '').toLowerCase();
      return DiscoveredServer(
        id: id,
        name: data['ServerName'] as String? ?? host,
        address: 'http://$host:$_jellyfinHttpPort',
        serverType: product.contains('emby')
            ? ServerType.emby
            : ServerType.jellyfin,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<InternetAddress>> _getBroadcastAddresses() async {
    final addresses = <InternetAddress>[InternetAddress('255.255.255.255')];
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final broadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              final broadcastAddr = InternetAddress(broadcast);
              if (!addresses.any((a) => a.address == broadcastAddr.address)) {
                addresses.add(broadcastAddr);
              }
            }
          }
        }
      }
    } catch (_) {}
    return addresses;
  }
}
