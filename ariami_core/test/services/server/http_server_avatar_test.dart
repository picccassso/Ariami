import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('user avatars', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late int port;
    late Uri baseUri;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_avatars_');
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );

      port = await _findFreePort();
      baseUri = Uri.parse('http://127.0.0.1:$port');
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

    test('authenticated upload then GET /api/me/avatar round-trips bytes',
        () async {
      final sessionToken = await _registerAndLogin(
        baseUri,
        username: 'owner',
        password: 'owner-pass',
        deviceId: 'owner-device',
      );
      final bytes = _jpegBytes();

      final upload = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
        contentType: ContentType('image', 'jpeg'),
        body: bytes,
      );
      expect(upload.statusCode, 200);
      final uploadJson = upload.jsonBody;
      expect(uploadJson['avatarUpdatedAt'], isA<int>());

      final getAvatar = await _sendBinaryRequest(
        method: 'GET',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
      );
      expect(getAvatar.statusCode, 200);
      expect(getAvatar.headers['content-type'], startsWith('image/jpeg'));
      expect(getAvatar.body, equals(bytes));
    });

    test('public user-avatar serves account avatars without auth', () async {
      final adminToken = await _registerAndLogin(
        baseUri,
        username: 'admin',
        password: 'admin-pass',
        deviceId: 'admin-device',
      );
      await _createUser(
        baseUri,
        adminToken: adminToken,
        username: 'Viewer',
        password: 'viewer-pass',
      );
      final viewerToken = await _login(
        baseUri,
        username: 'Viewer',
        password: 'viewer-pass',
        deviceId: 'viewer-device',
      );
      final bytes = _pngBytes();

      final upload = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(viewerToken),
        contentType: ContentType('image', 'png'),
        body: bytes,
      );
      expect(upload.statusCode, 200);

      final publicAvatar = await _sendBinaryRequest(
        method: 'GET',
        url: baseUri.resolve('/api/auth/user-avatar/Viewer?v=123'),
      );
      expect(publicAvatar.statusCode, 200);
      expect(publicAvatar.headers['content-type'], startsWith('image/png'));
      expect(publicAvatar.body, equals(bytes));
    });

    test('server-owner avatars are available to login pickers', () async {
      final adminToken = await _registerAndLogin(
        baseUri,
        username: 'admin',
        password: 'admin-pass',
        deviceId: 'admin-device',
      );

      final upload = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(adminToken),
        contentType: ContentType('image', 'jpeg'),
        body: _jpegBytes(),
      );
      expect(upload.statusCode, 200);

      final publicAvatar = await _sendBinaryRequest(
        method: 'GET',
        url: baseUri.resolve('/api/auth/user-avatar/admin'),
      );
      expect(publicAvatar.statusCode, 200);
      expect(publicAvatar.headers['content-type'], startsWith('image/jpeg'));
      expect(publicAvatar.body, equals(_jpegBytes()));
    });

    test('/api/auth/users entries carry avatar metadata', () async {
      final adminToken = await _registerAndLogin(
        baseUri,
        username: 'admin',
        password: 'admin-pass',
        deviceId: 'admin-device',
      );
      await _createUser(
        baseUri,
        adminToken: adminToken,
        username: 'listener',
        password: 'listener-pass',
      );
      final listenerToken = await _login(
        baseUri,
        username: 'listener',
        password: 'listener-pass',
        deviceId: 'listener-device',
      );

      final upload = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(listenerToken),
        contentType: ContentType('image', 'png'),
        body: _pngBytes(),
      );
      expect(upload.statusCode, 200);
      final avatarUpdatedAt = upload.jsonBody['avatarUpdatedAt'] as int;

      final users = await _sendJsonRequest(
        method: 'GET',
        url: baseUri.resolve('/api/auth/users'),
      );
      expect(users.statusCode, 200);
      final rows = (users.jsonBody['users'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(rows, hasLength(2));
      final owner = rows.singleWhere((row) => row['username'] == 'admin');
      expect(owner['hasAvatar'], isFalse);
      expect(owner['avatarUpdatedAt'], isNull);
      final listener = rows.singleWhere((row) => row['username'] == 'listener');
      expect(listener['hasAvatar'], isTrue);
      expect(listener['avatarUpdatedAt'], avatarUpdatedAt);

      final me = await _sendJsonRequest(
        method: 'GET',
        url: baseUri.resolve('/api/me'),
        headers: _authHeaders(listenerToken),
      );
      expect(me.statusCode, 200);
      expect(me.jsonBody['hasAvatar'], isTrue);
      expect(me.jsonBody['avatarUpdatedAt'], avatarUpdatedAt);
    });

    test('oversized and non-image uploads are rejected', () async {
      final sessionToken = await _registerAndLogin(
        baseUri,
        username: 'owner',
        password: 'owner-pass',
        deviceId: 'owner-device',
      );

      final oversized = Uint8List(5 * 1024 * 1024 + 1);
      oversized[0] = 0xFF;
      oversized[1] = 0xD8;
      oversized[2] = 0xFF;
      final tooLarge = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
        contentType: ContentType('image', 'jpeg'),
        body: oversized,
      );
      expect(tooLarge.statusCode, 413);

      final badBytes = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
        contentType: ContentType('image', 'png'),
        body: utf8.encode('not an image'),
      );
      expect(badBytes.statusCode, 400);

      final mismatched = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
        contentType: ContentType('image', 'png'),
        body: _jpegBytes(),
      );
      expect(mismatched.statusCode, 400);
    });

    test('DELETE /api/me/avatar is idempotent', () async {
      final sessionToken = await _registerAndLogin(
        baseUri,
        username: 'owner',
        password: 'owner-pass',
        deviceId: 'owner-device',
      );
      final upload = await _sendBinaryRequest(
        method: 'PUT',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
        contentType: ContentType('image', 'jpeg'),
        body: _jpegBytes(),
      );
      expect(upload.statusCode, 200);

      for (var i = 0; i < 2; i++) {
        final delete = await _sendBinaryRequest(
          method: 'DELETE',
          url: baseUri.resolve('/api/me/avatar'),
          headers: _authHeaders(sessionToken),
        );
        expect(delete.statusCode, 200);
        expect(delete.jsonBody, isEmpty);
      }

      final getAvatar = await _sendBinaryRequest(
        method: 'GET',
        url: baseUri.resolve('/api/me/avatar'),
        headers: _authHeaders(sessionToken),
      );
      expect(getAvatar.statusCode, 404);
    });
  });
}

Map<String, String> _authHeaders(String sessionToken) {
  return {'Authorization': 'Bearer $sessionToken'};
}

List<int> _jpegBytes() {
  return <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46];
}

List<int> _pngBytes() {
  return <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
  ];
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<String> _registerAndLogin(
  Uri baseUri, {
  required String username,
  required String password,
  required String deviceId,
}) async {
  final register = await _sendJsonRequest(
    method: 'POST',
    url: baseUri.resolve('/api/auth/register'),
    jsonBody: <String, dynamic>{
      'username': username,
      'password': password,
    },
  );
  expect(register.statusCode, 200);

  return _login(
    baseUri,
    username: username,
    password: password,
    deviceId: deviceId,
  );
}

Future<String> _login(
  Uri baseUri, {
  required String username,
  required String password,
  required String deviceId,
}) async {
  final login = await _sendJsonRequest(
    method: 'POST',
    url: baseUri.resolve('/api/auth/login'),
    jsonBody: <String, dynamic>{
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': '$deviceId name',
    },
  );
  expect(login.statusCode, 200);
  return login.jsonBody['sessionToken'] as String;
}

Future<void> _createUser(
  Uri baseUri, {
  required String adminToken,
  required String username,
  required String password,
}) async {
  final createUser = await _sendJsonRequest(
    method: 'POST',
    url: baseUri.resolve('/api/admin/create-user'),
    headers: _authHeaders(adminToken),
    jsonBody: <String, dynamic>{
      'username': username,
      'password': password,
    },
  );
  expect(createUser.statusCode, 201);
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
  final response = await _sendBinaryRequest(
    method: method,
    url: url,
    headers: headers,
    contentType: jsonBody == null ? null : ContentType.json,
    body: jsonBody == null ? null : utf8.encode(jsonEncode(jsonBody)),
  );
  return _JsonResponse(
    statusCode: response.statusCode,
    jsonBody: response.jsonBody,
  );
}

class _BinaryHttpResponse {
  _BinaryHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;

  Map<String, dynamic> get jsonBody {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  }
}

Future<_BinaryHttpResponse> _sendBinaryRequest({
  required String method,
  required Uri url,
  Map<String, String>? headers,
  ContentType? contentType,
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    headers?.forEach(request.headers.set);
    if (contentType != null) {
      request.headers.contentType = contentType;
    }
    if (body != null) {
      request.add(body);
    }

    final response = await request.close();

    final normalizedHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      normalizedHeaders[name.toLowerCase()] = values.join(', ');
    });

    final bytesBuilder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytesBuilder.add(chunk);
    }

    return _BinaryHttpResponse(
      statusCode: response.statusCode,
      headers: normalizedHeaders,
      body: bytesBuilder.takeBytes(),
    );
  } finally {
    client.close(force: true);
  }
}
