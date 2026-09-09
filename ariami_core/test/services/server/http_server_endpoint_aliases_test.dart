import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('HTTP server endpoint aliases', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.clearEndpointDiscoveryCallback();
      server.setPublicOrigin(null);
      server.setEndpointAliases(lanAlias: null, tailscaleAlias: null);
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_endpoint_aliases_');
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

    test('normalizes alias values and enforces 40 char limit', () {
      expect(AriamiHttpServer.normalizeEndpointAlias('  Home LAN  '), 'Home LAN');
      expect(AriamiHttpServer.normalizeEndpointAlias('   '), isNull);
      expect(AriamiHttpServer.normalizeEndpointAlias(null), isNull);

      final exactly40 = 'a' * 40;
      expect(AriamiHttpServer.normalizeEndpointAlias(exactly40), exactly40);

      final chars41 = 'a' * 41;
      expect(
        () => AriamiHttpServer.normalizeEndpointAlias(chars41),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setEndpointAliases exposes aliases in getServerInfo', () async {
      server.setEndpointAliases(
        lanAlias: 'Living Room',
        tailscaleAlias: 'Studio Remote',
      );

      final info = server.getServerInfo();
      expect(info['lanServerAlias'], 'Living Room');
      expect(info['tailscaleServerAlias'], 'Studio Remote');
    });

    test('POST /api/server-info/aliases requires admin auth when users exist', () async {
      await server.start(
        advertisedIp: '127.0.0.1',
        lanIp: '192.168.1.100',
        tailscaleIp: '100.64.0.1',
        bindAddress: '127.0.0.1',
        port: 0,
      );
      final port = server.getServerInfo()['port'] as int;
      final adminToken = await _registerAndLogin(port);

      // Unauthenticated request fails
      final url = Uri.parse('http://127.0.0.1:$port/api/server-info/aliases');
      final (anonStatus, _) = await _httpPost(
        url,
        jsonBody: {'lanAlias': 'Sneaky LAN'},
      );
      expect(anonStatus, anyOf(401, 403));

      // Authenticated admin request succeeds
      String? callbackLan;
      String? callbackTailscale;
      server.setOnEndpointAliasesChanged(
        ({String? lanAlias, String? tailscaleAlias}) async {
          callbackLan = lanAlias;
          callbackTailscale = tailscaleAlias;
        },
      );

      final (authStatus, authBody) = await _httpPost(
        url,
        headers: {'Authorization': 'Bearer $adminToken'},
        jsonBody: {
          'lanAlias': 'Home Studio',
          'tailscaleAlias': 'My Tailscale',
        },
      );
      expect(authStatus, 200);

      final responseJson = jsonDecode(authBody) as Map<String, dynamic>;
      expect(responseJson['success'], isTrue);
      expect(responseJson['lanServerAlias'], 'Home Studio');
      expect(responseJson['tailscaleServerAlias'], 'My Tailscale');

      expect(callbackLan, 'Home Studio');
      expect(callbackTailscale, 'My Tailscale');

      // Check /api/server-info reflects the new aliases
      final infoUrl = Uri.parse('http://127.0.0.1:$port/api/server-info');
      final (_, infoBody) = await _httpGet(infoUrl);
      final info = jsonDecode(infoBody) as Map<String, dynamic>;
      expect(info['lanServerAlias'], 'Home Studio');
      expect(info['tailscaleServerAlias'], 'My Tailscale');

      // Clearing alias by sending empty string
      final (clearStatus, _) = await _httpPost(
        url,
        headers: {'Authorization': 'Bearer $adminToken'},
        jsonBody: {'lanAlias': ''},
      );
      expect(clearStatus, 200);

      final (_, clearedInfoBody) = await _httpGet(infoUrl);
      final clearedInfo = jsonDecode(clearedInfoBody) as Map<String, dynamic>;
      expect(clearedInfo.containsKey('lanServerAlias'), isFalse);
      expect(clearedInfo['tailscaleServerAlias'], 'My Tailscale');
    });

    test('POST /api/server-info/aliases rejects aliases over 40 characters', () async {
      await server.start(
        advertisedIp: '127.0.0.1',
        lanIp: '192.168.1.100',
        bindAddress: '127.0.0.1',
        port: 0,
      );
      final port = server.getServerInfo()['port'] as int;
      final adminToken = await _registerAndLogin(port);

      final url = Uri.parse('http://127.0.0.1:$port/api/server-info/aliases');
      final (badStatus, badBody) = await _httpPost(
        url,
        headers: {'Authorization': 'Bearer $adminToken'},
        jsonBody: {'lanAlias': 'a' * 41},
      );
      expect(badStatus, 400);
      expect(badBody, contains('40 characters'));
    });
  });
}

Future<String> _registerAndLogin(int port) async {
  final registerUrl = Uri.parse('http://127.0.0.1:$port/api/auth/register');
  final (registerStatus, _) = await _httpPost(
    registerUrl,
    jsonBody: <String, dynamic>{
      'username': 'alias-owner',
      'password': 'alias-password-123',
    },
  );
  expect(registerStatus, 200);

  final loginUrl = Uri.parse('http://127.0.0.1:$port/api/auth/login');
  final (loginStatus, loginBody) = await _httpPost(
    loginUrl,
    jsonBody: <String, dynamic>{
      'username': 'alias-owner',
      'password': 'alias-password-123',
      'deviceId': 'alias-device',
      'deviceName': 'Alias Device',
    },
  );
  expect(loginStatus, 200);

  final json = jsonDecode(loginBody) as Map<String, dynamic>;
  return json['sessionToken'] as String;
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

Future<(int status, String body)> _httpPost(
  Uri url, {
  Map<String, String>? headers,
  Map<String, dynamic>? jsonBody,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    headers?.forEach(request.headers.set);
    if (jsonBody != null) {
      request.write(jsonEncode(jsonBody));
    }
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}
