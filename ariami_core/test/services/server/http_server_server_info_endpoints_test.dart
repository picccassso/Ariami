import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Regression: CLI/Desktop must pass [tailscaleIp] and [lanIp] into [AriamiHttpServer.start]
/// so `/api/server-info` exposes both for mobile LAN preference.
void main() {
  group('HTTP server /api/server-info endpoint fields', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_server_info_ep_');
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('getServerInfo is safe before auth initialization', () async {
      final info = server.getServerInfo();

      expect(info['hasUsers'], isFalse);
      expect(info['registeredUsers'], 0);
    });

    test('includes lanServer and tailscaleServer when both are set', () async {
      const tsIp = '100.64.10.20';
      const lan = '192.168.1.50';
      final port = await _findFreePort();

      await server.start(
        advertisedIp: tsIp,
        tailscaleIp: tsIp,
        lanIp: lan,
        bindAddress: '127.0.0.1',
        port: port,
      );

      final (status, body) = await _httpGet(
        Uri.parse('http://127.0.0.1:$port/api/server-info'),
      );
      expect(status, 200);

      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['server'], tsIp);
      expect(json['tailscaleServer'], tsIp);
      expect(json['lanServer'], lan);
      expect(json['port'], port);
      expect(json['hasUsers'], isFalse);
      expect(json['registeredUsers'], 0);
    });

    test('LAN-only start exposes lanServer and null tailscaleServer', () async {
      const lan = '10.0.0.2';
      final port = await _findFreePort();

      await server.start(
        advertisedIp: lan,
        tailscaleIp: null,
        lanIp: lan,
        bindAddress: '127.0.0.1',
        port: port,
      );

      final (status, body) = await _httpGet(
        Uri.parse('http://127.0.0.1:$port/api/server-info'),
      );
      expect(status, 200);

      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['server'], lan);
      expect(json['lanServer'], lan);
      expect(json['tailscaleServer'], isNull);
    });

    test('updateAdvertisedEndpoints updates /api/server-info', () async {
      const lan = '192.168.1.50';
      const tsIp = '100.64.10.20';
      final port = await _findFreePort();

      await server.start(
        advertisedIp: lan,
        tailscaleIp: null,
        lanIp: lan,
        bindAddress: '127.0.0.1',
        port: port,
      );

      final changed = server.updateAdvertisedEndpoints(
        tailscaleIp: tsIp,
        lanIp: lan,
      );
      expect(changed, isTrue);

      final (status, body) = await _httpGet(
        Uri.parse('http://127.0.0.1:$port/api/server-info'),
      );
      expect(status, 200);

      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['server'], tsIp);
      expect(json['tailscaleServer'], tsIp);
      expect(json['lanServer'], lan);
    });

    test('updateAdvertisedEndpoints emits onEndpointsChanged', () async {
      const lan = '10.0.0.2';
      final port = await _findFreePort();

      await server.start(
        advertisedIp: lan,
        tailscaleIp: null,
        lanIp: lan,
        bindAddress: '127.0.0.1',
        port: port,
      );

      final events = <Map<String, dynamic>>[];
      final subscription = server.onEndpointsChanged.listen(events.add);

      server.updateAdvertisedEndpoints(
        tailscaleIp: '100.64.10.20',
        lanIp: lan,
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first['tailscaleServer'], '100.64.10.20');

      await subscription.cancel();
    });

    test('endpoint discovery callback updates stored endpoints', () async {
      const lan = '192.168.1.50';
      var tailscaleIp = '100.64.10.20';
      final port = await _findFreePort();

      server.setEndpointDiscoveryCallback(() async {
        return NetworkEndpoints(
          tailscaleIp: tailscaleIp,
          lanIp: lan,
        );
      });

      await server.start(
        advertisedIp: lan,
        tailscaleIp: null,
        lanIp: lan,
        bindAddress: '127.0.0.1',
        port: port,
      );

      tailscaleIp = '100.64.10.99';
      server.updateAdvertisedEndpoints(
        tailscaleIp: tailscaleIp,
        lanIp: lan,
      );

      final info = server.getServerInfo();
      expect(info['tailscaleServer'], '100.64.10.99');
      expect(info['server'], '100.64.10.99');
    });

    test('server-info refresh endpoint runs endpoint discovery immediately',
        () async {
      const initialLan = '192.168.1.50';
      var lan = initialLan;
      final port = await _findFreePort();

      server.setEndpointDiscoveryCallback(() async {
        return NetworkEndpoints(lanIp: lan);
      });

      await server.start(
        advertisedIp: initialLan,
        tailscaleIp: null,
        lanIp: initialLan,
        bindAddress: '127.0.0.1',
        port: port,
      );

      lan = '192.168.1.88';
      final (status, body) = await _httpPost(
        Uri.parse('http://127.0.0.1:$port/api/server-info/refresh'),
      );
      expect(status, 200);

      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['server'], lan);
      expect(json['lanServer'], lan);
      expect(json['tailscaleServer'], isNull);
    });
  });
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<(int status, String body)> _httpGet(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

Future<(int status, String body)> _httpPost(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}
