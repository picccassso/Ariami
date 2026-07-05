import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GET /api/auth/users', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_auth_users_');
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

    test('is public and returns every account sorted by username', () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final emptyResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/users'),
      );
      expect(emptyResponse.statusCode, 200);
      expect(emptyResponse.jsonBody.keys, unorderedEquals(['users']));
      expect(emptyResponse.jsonBody['users'], isEmpty);

      final adminUsername = 'zeta';
      final registerOwner = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': adminUsername,
          'password': 'zeta-pass',
        },
      );
      expect(registerOwner.statusCode, 200);

      final ownerLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': adminUsername,
          'password': 'zeta-pass',
          'deviceId': 'owner-device',
          'deviceName': 'Owner Device',
        },
      );
      expect(ownerLogin.statusCode, 200);
      final ownerToken = ownerLogin.jsonBody['sessionToken'] as String;

      for (final username in ['Beta', 'alpha']) {
        final createUser = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/admin/create-user'),
          headers: <String, String>{'Authorization': 'Bearer $ownerToken'},
          jsonBody: <String, dynamic>{
            'username': username,
            'password': '$username-pass',
          },
        );
        expect(createUser.statusCode, 201);
      }

      final usersResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/users'),
      );
      expect(usersResponse.statusCode, 200);
      expect(usersResponse.jsonBody.keys, unorderedEquals(['users']));

      final users = (usersResponse.jsonBody['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        users.map((user) => user['username']).toList(),
        equals(['alpha', 'Beta', adminUsername]),
      );
      for (final user in users) {
        expect(
          user.keys,
          unorderedEquals(['username', 'hasAvatar', 'avatarUpdatedAt']),
        );
        expect(user['hasAvatar'], isFalse);
        expect(user['avatarUpdatedAt'], isNull);
      }
    });
  });
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _JsonResponse {
  const _JsonResponse({
    required this.statusCode,
    required this.jsonBody,
  });

  final int statusCode;
  final Map<String, dynamic> jsonBody;
}

Future<_JsonResponse> _sendJsonRequest({
  required String method,
  required Uri url,
  Map<String, String>? headers,
  Map<String, dynamic>? jsonBody,
}) async {
  final client = HttpClient();
  try {
    final request =
        method == 'POST' ? await client.postUrl(url) : await client.getUrl(url);

    final mergedHeaders = <String, String>{
      if (headers != null) ...headers,
      if (jsonBody != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    mergedHeaders.forEach(request.headers.set);

    if (jsonBody != null) {
      request.write(jsonEncode(jsonBody));
    }

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decodedBody = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;

    return _JsonResponse(
      statusCode: response.statusCode,
      jsonBody: decodedBody,
    );
  } finally {
    client.close(force: true);
  }
}
