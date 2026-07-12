import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/license/license_file_store.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late AriamiHttpServer server;
  late Directory directory;
  late int port;
  late String adminToken;
  late String memberToken;

  setUp(() async {
    server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    directory = await Directory.systemTemp.createTemp('ariami_http_license_');
    server.libraryManager
        .setCachePath(p.join(directory.path, 'metadata_cache.json'));
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    // First registered user is the admin.
    await AuthService().register('owner', 'owner-pass-123456');
    await AuthService().register('member', 'member-pass-123456');
    port = await _freePort();
    await server.start(
      advertisedIp: '127.0.0.1',
      bindAddress: '127.0.0.1',
      port: port,
    );
    adminToken = await _login(port, 'owner', 'owner-pass-123456', 'device-o');
    memberToken =
        await _login(port, 'member', 'member-pass-123456', 'device-m');
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  test('GET requires authentication', () async {
    final response = await _request(port, 'GET', '/api/license');
    expect(response.statusCode, 401);
  });

  test('GET reports a null licenseFile while nothing is stored', () async {
    final response =
        await _request(port, 'GET', '/api/license', token: memberToken);
    expect(response.statusCode, 200);
    expect(response.json['schemaVersion'], 2);
    expect(response.json['licenseFile'], isNull);
    expect(response.json['licenseFiles'], isEmpty);
  });

  test('PUT and DELETE are admin-only', () async {
    final put = await _request(
      port,
      'PUT',
      '/api/license',
      token: memberToken,
      body: {'licenseFile': 'OPAQUE.blob'},
    );
    final delete =
        await _request(port, 'DELETE', '/api/license', token: memberToken);
    expect(put.statusCode, 403);
    expect(delete.statusCode, 403);
  });

  test('admin stores a file; any signed-in device fetches it verbatim',
      () async {
    const blob = 'ARIAMI1.some-opaque-payload.some-opaque-signature';
    final put = await _request(
      port,
      'PUT',
      '/api/license',
      token: adminToken,
      body: {'licenseFile': blob},
    );
    expect(put.statusCode, 200);
    expect(put.json['stored'], isTrue);

    final fetched =
        await _request(port, 'GET', '/api/license', token: memberToken);
    expect(fetched.statusCode, 200);
    expect(fetched.json['schemaVersion'], 2);
    expect(fetched.json['licenseFile'], blob);
    expect(fetched.json['licenseFiles'], [blob]);
  });

  test('storing a second file keeps both; the newest doubles as licenseFile',
      () async {
    for (final blob in ['FIRST.blob.sig', 'SECOND.blob.sig']) {
      await _request(
        port,
        'PUT',
        '/api/license',
        token: adminToken,
        body: {'licenseFile': blob},
      );
    }
    final fetched =
        await _request(port, 'GET', '/api/license', token: adminToken);
    expect(fetched.json['licenseFile'], 'SECOND.blob.sig');
    expect(
      fetched.json['licenseFiles'],
      ['FIRST.blob.sig', 'SECOND.blob.sig'],
    );
  });

  test('malformed and oversized bodies are rejected', () async {
    final missingKey = await _request(
      port,
      'PUT',
      '/api/license',
      token: adminToken,
      body: {'wrongKey': 'x'},
    );
    final emptyValue = await _request(
      port,
      'PUT',
      '/api/license',
      token: adminToken,
      body: {'licenseFile': '   '},
    );
    final oversized = await _request(
      port,
      'PUT',
      '/api/license',
      token: adminToken,
      body: {
        'licenseFile': 'A' * (LicenseFileStore.maxLicenseFileBytes + 1),
      },
    );
    final oversizedUtf8 = await _request(
      port,
      'PUT',
      '/api/license',
      token: adminToken,
      body: {
        'licenseFile': 'é' * (LicenseFileStore.maxLicenseFileBytes ~/ 2 + 1),
      },
    );
    for (final response in [
      missingKey,
      emptyValue,
      oversized,
      oversizedUtf8,
    ]) {
      expect(response.statusCode, 400);
      expect((response.json['error'] as Map)['code'], 'INVALID_LICENSE_BODY');
    }
  });

  test('DELETE removes every stored file', () async {
    for (final blob in ['FIRST.blob.sig', 'SECOND.blob.sig']) {
      await _request(
        port,
        'PUT',
        '/api/license',
        token: adminToken,
        body: {'licenseFile': blob},
      );
    }
    final delete =
        await _request(port, 'DELETE', '/api/license', token: adminToken);
    expect(delete.statusCode, 200);
    expect(delete.json['removed'], isTrue);

    final fetched =
        await _request(port, 'GET', '/api/license', token: adminToken);
    expect(fetched.statusCode, 200);
    expect(fetched.json['licenseFile'], isNull);
    expect(fetched.json['licenseFiles'], isEmpty);
  });

  test('stored file survives an auth reinitialize on the same directory',
      () async {
    await _request(
      port,
      'PUT',
      '/api/license',
      token: adminToken,
      body: {'licenseFile': 'DURABLE.blob.sig'},
    );
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    await AuthService().register('owner2', 'owner2-pass-123456');
    final token =
        await _login(port, 'owner2', 'owner2-pass-123456', 'device-o2');
    final fetched = await _request(port, 'GET', '/api/license', token: token);
    expect(fetched.statusCode, 200);
    expect(fetched.json['licenseFile'], 'DURABLE.blob.sig');
  });
}

Future<String> _login(
  int port,
  String username,
  String password,
  String deviceId,
) async {
  final response = await _request(
    port,
    'POST',
    '/api/auth/login',
    body: {
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceId,
    },
  );
  expect(response.statusCode, 200);
  return response.json['sessionToken'] as String;
}

Future<_Response> _request(
  int port,
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return _Response(
      response.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _Response {
  const _Response(this.statusCode, this.json);
  final int statusCode;
  final Map<String, dynamic> json;
}
