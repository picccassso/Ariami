import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

/// First-owner bootstrap gating: while no accounts exist, `POST
/// /api/auth/register` must reject non-local clients unless they present the
/// setup code shown on the server's own console.
///
/// The deny path only runs for a genuinely non-loopback peer, so these tests
/// connect to a reachable address on the machine itself (the socket's remote
/// address is then the LAN/VPN IP, not 127.0.0.1). Merely enumerating an
/// adapter is not enough: CI hosts can expose dormant virtual interfaces, so
/// the helper probes each candidate against the running test server first.
void main() {
  group('first-owner bootstrap gating', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late int port;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_bootstrap_');
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );

      server.setDiscoveryResponderEnabled(false);
      port = await startHttpTestServer(
        server,
        bindAddress: '0.0.0.0',
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('loopback owner registration needs no code', () async {
      final response = await _register(
        host: '127.0.0.1',
        port: port,
        username: 'local-owner',
        password: 'local-owner-pass',
      );
      expect(response.statusCode, 200);
      expect(response.jsonBody['username'], 'local-owner');

      // Once an owner exists there is no bootstrap code to hand out.
      expect(server.getOrCreateOwnerBootstrapCode(), isNull);
    });

    test('remote owner registration is rejected without the setup code',
        () async {
      final lanIp = await _findReachableNonLoopbackIPv4(port);
      if (lanIp == null) {
        markTestSkipped(
          'No reachable non-loopback IPv4 interface on this machine.',
        );
        return;
      }

      final denied = await _register(
        host: lanIp,
        port: port,
        username: 'remote-owner',
        password: 'remote-owner-pass',
      );
      expect(denied.statusCode, 403);
      expect(
        (denied.jsonBody['error'] as Map)['code'],
        'OWNER_BOOTSTRAP_REQUIRED',
      );

      final wrongCode = await _register(
        host: lanIp,
        port: port,
        username: 'remote-owner',
        password: 'remote-owner-pass',
        bootstrapCode: 'NOT-THE-CODE',
      );
      expect(wrongCode.statusCode, 403);
      expect(server.getOrCreateOwnerBootstrapCode(), isNotNull,
          reason: 'a failed attempt must not consume the code');
    });

    test('remote owner registration succeeds with the console setup code',
        () async {
      final lanIp = await _findReachableNonLoopbackIPv4(port);
      if (lanIp == null) {
        markTestSkipped(
          'No reachable non-loopback IPv4 interface on this machine.',
        );
        return;
      }

      final code = server.getOrCreateOwnerBootstrapCode();
      expect(code, isNotNull);

      // Typed the way the console shows it: grouped and case-insensitive.
      final typedCode =
          '${code!.substring(0, 4)}-${code.substring(4)}'.toLowerCase();
      final accepted = await _register(
        host: lanIp,
        port: port,
        username: 'remote-owner',
        password: 'remote-owner-pass',
        bootstrapCode: typedCode,
      );
      expect(accepted.statusCode, 200);
      expect(accepted.jsonBody['username'], 'remote-owner');

      // The code is single-purpose: gone once the owner exists, and later
      // registrations fall under the normal invite/QR gating.
      expect(server.getOrCreateOwnerBootstrapCode(), isNull);

      final secondUser = await _register(
        host: lanIp,
        port: port,
        username: 'second-user',
        password: 'second-user-pass',
        bootstrapCode: typedCode,
      );
      expect(secondUser.statusCode, 403);
      expect(
        (secondUser.jsonBody['error'] as Map)['code'],
        'REGISTRATION_CLOSED',
      );
    });
  });
}

/// A reachable non-loopback IPv4 address of this machine, so the HTTP server
/// observes a genuinely remote peer. Virtual/VPN adapters may be enumerated
/// while dormant; probing avoids selecting one that cannot route locally.
Future<String?> _findReachableNonLoopbackIPv4(int port) async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (address.isLoopback || address.isLinkLocal) continue;
      Socket? probe;
      try {
        probe = await Socket.connect(
          address,
          port,
          timeout: const Duration(seconds: 1),
        );
        return address.address;
      } on SocketException {
        // Try the next adapter. CI often exposes unreachable virtual NICs.
      } finally {
        probe?.destroy();
      }
    }
  }
  return null;
}

class _JsonResponse {
  const _JsonResponse({required this.statusCode, required this.jsonBody});

  final int statusCode;
  final Map<String, dynamic> jsonBody;
}

Future<_JsonResponse> _register({
  required String host,
  required int port,
  required String username,
  required String password,
  String? bootstrapCode,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 3);
  try {
    final request =
        await client.postUrl(Uri.parse('http://$host:$port/api/auth/register'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{
      'username': username,
      'password': password,
      if (bootstrapCode != null) 'bootstrapCode': bootstrapCode,
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return _JsonResponse(
      statusCode: response.statusCode,
      jsonBody: body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}
