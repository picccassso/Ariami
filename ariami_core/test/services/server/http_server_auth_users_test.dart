import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GET /api/auth/users', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late int port;
    Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

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

      port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    Future<String> registerAndLoginOwner() async {
      final register = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'zeta',
          'password': 'zeta-pass-123',
        },
      );
      expect(register.statusCode, 200);

      final login = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'zeta',
          'password': 'zeta-pass-123',
          'deviceId': 'owner-device',
          'deviceName': 'Owner Device',
        },
      );
      expect(login.statusCode, 200);
      return login.jsonBody['sessionToken'] as String;
    }

    test('is disabled by default; no usernames leak pre-auth', () async {
      // Default off: privacy-preserving without any host wiring.
      final defaultResponse = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(defaultResponse.statusCode, 403);
      expect(
        (defaultResponse.jsonBody['error'] as Map)['code'],
        'USER_PICKER_DISABLED',
      );

      await registerAndLoginOwner();

      // Still off after accounts exist: no usernames leak.
      final disabledWithUsers = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(disabledWithUsers.statusCode, 403);
      expect(disabledWithUsers.jsonBody.toString(), isNot(contains('zeta')));

      // The public avatar endpoint must not confirm the username exists.
      final avatar = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/user-avatar/zeta'),
      );
      expect(avatar.statusCode, 404);

      // The owner opts in: the endpoint answers.
      server.setPublicUserPickerEnabled(true);
      final enabled = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(enabled.statusCode, 200);
      expect(
        (enabled.jsonBody['users'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((user) => user['username']),
        contains('zeta'),
      );
    });

    test('when enabled, returns every account sorted by username', () async {
      server.setPublicUserPickerEnabled(true);
      final emptyResponse = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(emptyResponse.statusCode, 200);
      expect(emptyResponse.jsonBody.keys, unorderedEquals(['users']));
      expect(emptyResponse.jsonBody['users'], isEmpty);

      final ownerToken = await registerAndLoginOwner();

      for (final username in ['Beta', 'alpha']) {
        final createUser = await _sendJsonRequest(
          method: 'POST',
          url: url('/api/admin/create-user'),
          headers: <String, String>{'Authorization': 'Bearer $ownerToken'},
          jsonBody: <String, dynamic>{
            'username': username,
            'password': '$username-pass-123',
          },
        );
        expect(createUser.statusCode, 201);
      }

      final usersResponse = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(usersResponse.statusCode, 200);
      expect(usersResponse.jsonBody.keys, unorderedEquals(['users']));

      final users = (usersResponse.jsonBody['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        users.map((user) => user['username']).toList(),
        equals(['alpha', 'Beta', 'zeta']),
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

    test('admin endpoint toggles the picker at runtime', () async {
      final ownerToken = await registerAndLoginOwner();
      final adminHeaders = <String, String>{
        'Authorization': 'Bearer $ownerToken',
      };

      // Read requires admin; unauthenticated is rejected.
      final unauthedGet = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/admin/user-picker'),
      );
      expect(unauthedGet.statusCode, 401);

      final initialState = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/admin/user-picker'),
        headers: adminHeaders,
      );
      expect(initialState.statusCode, 200);
      expect(initialState.jsonBody['enabled'], isFalse);

      // Unauthenticated toggle attempts are rejected and change nothing.
      final unauthedSet = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/admin/user-picker'),
        jsonBody: <String, dynamic>{'enabled': true},
      );
      expect(unauthedSet.statusCode, 401);
      expect(server.publicUserPickerEnabled, isFalse);

      // Bad payloads are rejected.
      final badSet = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/admin/user-picker'),
        headers: adminHeaders,
        jsonBody: <String, dynamic>{'enabled': 'yes'},
      );
      expect(badSet.statusCode, 400);

      // Enable: the public listing answers.
      final enable = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/admin/user-picker'),
        headers: adminHeaders,
        jsonBody: <String, dynamic>{'enabled': true},
      );
      expect(enable.statusCode, 200);
      expect(enable.jsonBody['enabled'], isTrue);

      final publicList = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(publicList.statusCode, 200);
      expect(
        (publicList.jsonBody['users'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((user) => user['username']),
        contains('zeta'),
      );

      // Disable again: the public listing stops answering.
      final disable = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/admin/user-picker'),
        headers: adminHeaders,
        jsonBody: <String, dynamic>{'enabled': false},
      );
      expect(disable.statusCode, 200);
      expect(disable.jsonBody['enabled'], isFalse);

      final disabledList = await _sendJsonRequest(
        method: 'GET',
        url: url('/api/auth/users'),
      );
      expect(disabledList.statusCode, 403);
    });

    test('admin toggle invokes the host persistence callback', () async {
      final ownerToken = await registerAndLoginOwner();
      final adminHeaders = <String, String>{
        'Authorization': 'Bearer $ownerToken',
      };

      final persisted = <bool>[];
      server.setPublicUserPickerPersistCallback((enabled) async {
        persisted.add(enabled);
      });

      for (final enabled in [true, false]) {
        final response = await _sendJsonRequest(
          method: 'POST',
          url: url('/api/admin/user-picker'),
          headers: adminHeaders,
          jsonBody: <String, dynamic>{'enabled': enabled},
        );
        expect(response.statusCode, 200);
      }
      expect(persisted, equals([true, false]));

      // A persist failure surfaces as 500, but the runtime state still
      // applies (the admin can retry; the toggle works until restart).
      server.setPublicUserPickerPersistCallback((_) async {
        throw StateError('disk full');
      });
      final failed = await _sendJsonRequest(
        method: 'POST',
        url: url('/api/admin/user-picker'),
        headers: adminHeaders,
        jsonBody: <String, dynamic>{'enabled': true},
      );
      expect(failed.statusCode, 500);
      expect((failed.jsonBody['error'] as Map)['code'], 'PERSIST_FAILED');
      expect(server.publicUserPickerEnabled, isTrue);
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
    // Some endpoints (avatar 404s) answer with plain-text bodies.
    Map<String, dynamic> decodedBody;
    try {
      decodedBody = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      decodedBody = <String, dynamic>{'raw': body};
    }

    return _JsonResponse(
      statusCode: response.statusCode,
      jsonBody: decodedBody,
    );
  } finally {
    client.close(force: true);
  }
}
