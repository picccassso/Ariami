import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AriamiHttpServer.startWithPortFallback', () {
    late AriamiHttpServer server;
    late Directory testDir;
    HttpServer? blocker;

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
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      await blocker?.close(force: true);
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('falls back to the configured range when preferred port is busy',
        () async {
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final preferredPort = blocker!.port;

      final resolvedPort = await server.startWithPortFallback(
        advertisedIp: '127.0.0.1',
        tailscaleIp: null,
        lanIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        preferredPort: preferredPort,
        allowFallback: true,
      );

      expect(resolvedPort, isNot(preferredPort));
      expect(resolvedPort, inInclusiveRange(8080, 8099));

      final info = server.getServerInfo();
      expect(info['port'], resolvedPort);
      expect(info['attemptedPort'], preferredPort);
      expect(info['portFallbackUsed'], isTrue);

      final (status, _) = await _httpGet(
        Uri.parse('http://127.0.0.1:$resolvedPort/api/server-info'),
      );
      expect(status, 200);
    });

    test('throws PortBindingException when fallback disabled and port busy',
        () async {
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final preferredPort = blocker!.port;

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
      blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final savedPort = blocker!.port;
      final preferredBlocker =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final preferredPort = preferredBlocker.port;

      try {
        final resolvedPort = await server.startWithPortFallback(
          advertisedIp: '127.0.0.1',
          tailscaleIp: null,
          lanIp: '127.0.0.1',
          bindAddress: '127.0.0.1',
          preferredPort: preferredPort,
          savedPort: savedPort,
          allowFallback: true,
        );

        expect(resolvedPort, isNot(anyOf(savedPort, preferredPort)));
        expect(server.getServerInfo()['attemptedPort'], savedPort);
        expect(server.getServerInfo()['portFallbackUsed'], isTrue);
      } finally {
        await preferredBlocker.close(force: true);
      }
    });
  });
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
