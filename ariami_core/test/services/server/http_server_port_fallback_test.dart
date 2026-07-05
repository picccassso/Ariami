import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AriamiHttpServer.startWithPortFallback', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late HttpServer blocker;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_port_fb_');
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      await blocker.close(force: true);
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      await blocker.close(force: true);
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('falls back to next port when preferred port is busy', () async {
      final preferredPort = await _findFreePortInRange(8080, 8098);
      final expectedPort = preferredPort + 1;
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort);

      final resolvedPort = await server.startWithPortFallback(
        advertisedIp: '127.0.0.1',
        tailscaleIp: null,
        lanIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        preferredPort: preferredPort,
        allowFallback: true,
      );

      expect(resolvedPort, expectedPort);

      final info = server.getServerInfo();
      expect(info['port'], expectedPort);
      expect(info['attemptedPort'], preferredPort);
      expect(info['portFallbackUsed'], isTrue);

      final (status, _) = await _httpGet(
        Uri.parse('http://127.0.0.1:$expectedPort/api/server-info'),
      );
      expect(status, 200);
    });

    test('throws PortBindingException when fallback disabled and port busy',
        () async {
      final preferredPort = await _findFreePort();
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort);

      expect(
        () => server.startWithPortFallback(
          advertisedIp: '127.0.0.1',
          tailscaleIp: null,
          lanIp: '127.0.0.1',
          bindAddress: '127.0.0.1',
          preferredPort: preferredPort,
          allowFallback: false,
        ),
        throwsA(isA<PortBindingException>()),
      );
    });

    test('uses saved port before preferred port in candidate order', () async {
      final savedPort = await _findFreePortInRange(8080, 8098);
      final preferredPort = savedPort + 1;
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, savedPort);

      final resolvedPort = await server.startWithPortFallback(
        advertisedIp: '127.0.0.1',
        tailscaleIp: null,
        lanIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        preferredPort: preferredPort,
        savedPort: savedPort,
        allowFallback: true,
      );

      expect(resolvedPort, preferredPort);
      expect(server.getServerInfo()['attemptedPort'], savedPort);
      expect(server.getServerInfo()['portFallbackUsed'], isTrue);
    });
  });
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<int> _findFreePortInRange(int start, int end) async {
  for (var port = start; port <= end; port++) {
    try {
      final socket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return port;
    } on SocketException {
      continue;
    }
  }
  throw StateError('No free port found in range $start-$end');
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
