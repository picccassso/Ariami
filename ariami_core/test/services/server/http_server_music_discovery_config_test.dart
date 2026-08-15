import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/recommendations/household_music_discovery_store.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

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
    directory = await Directory.systemTemp.createTemp('ariami_http_discovery_');
    server.libraryManager
        .setCachePath(p.join(directory.path, 'metadata_cache.json'));
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    await AuthService().register('owner', 'owner-pass-123456');
    await AuthService().register('member', 'member-pass-123456');
    port = await startHttpTestServer(server);
    adminToken = await _login(port, 'owner', 'owner-pass-123456', 'device-o');
    memberToken =
        await _login(port, 'member', 'member-pass-123456', 'device-m');
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  test('GET requires authentication and starts unconfigured', () async {
    final unauthenticated =
        await _request(port, 'GET', '/api/music-discovery/config');
    expect(unauthenticated.statusCode, 401);

    final owner = await _request(
      port,
      'GET',
      '/api/music-discovery/config',
      token: adminToken,
    );
    final member = await _request(
      port,
      'GET',
      '/api/music-discovery/config',
      token: memberToken,
    );
    expect(owner.statusCode, 200);
    expect(owner.json, containsPair('schemaVersion', 1));
    expect(owner.json['lastFmApiKey'], isNull);
    expect(owner.json['canManage'], isTrue);
    expect(member.json['canManage'], isFalse);
  });

  test('only the owner may write or delete the household key', () async {
    final memberPut = await _request(
      port,
      'PUT',
      '/api/music-discovery/config',
      token: memberToken,
      body: <String, dynamic>{'lastFmApiKey': 'member-key'},
    );
    final memberDelete = await _request(
      port,
      'DELETE',
      '/api/music-discovery/config',
      token: memberToken,
    );
    expect(memberPut.statusCode, 403);
    expect(memberDelete.statusCode, 403);
  });

  test('owner stores once and every signed-in device receives the key',
      () async {
    final put = await _request(
      port,
      'PUT',
      '/api/music-discovery/config',
      token: adminToken,
      body: <String, dynamic>{'lastFmApiKey': '  shared-key  '},
    );
    expect(put.statusCode, 200);
    expect(put.json['lastFmApiKey'], 'shared-key');
    expect(put.json['canManage'], isTrue);

    final fetched = await _request(
      port,
      'GET',
      '/api/music-discovery/config',
      token: memberToken,
    );
    expect(fetched.statusCode, 200);
    expect(fetched.json['lastFmApiKey'], 'shared-key');
    expect(fetched.json['canManage'], isFalse);
  });

  test('onlyIfMissing migration never overwrites an existing household key',
      () async {
    await _request(
      port,
      'PUT',
      '/api/music-discovery/config',
      token: adminToken,
      body: <String, dynamic>{
        'lastFmApiKey': 'first-device-key',
        'onlyIfMissing': true,
      },
    );
    final second = await _request(
      port,
      'PUT',
      '/api/music-discovery/config',
      token: adminToken,
      body: <String, dynamic>{
        'lastFmApiKey': 'second-device-key',
        'onlyIfMissing': true,
      },
    );
    expect(second.statusCode, 200);
    expect(second.json['lastFmApiKey'], 'first-device-key');
  });

  test('malformed, empty, and oversized keys are rejected', () async {
    final responses = <_Response>[
      await _request(
        port,
        'PUT',
        '/api/music-discovery/config',
        token: adminToken,
        body: <String, dynamic>{'wrongKey': 'x'},
      ),
      await _request(
        port,
        'PUT',
        '/api/music-discovery/config',
        token: adminToken,
        body: <String, dynamic>{'lastFmApiKey': '   '},
      ),
      await _request(
        port,
        'PUT',
        '/api/music-discovery/config',
        token: adminToken,
        body: <String, dynamic>{
          'lastFmApiKey':
              'A' * (HouseholdMusicDiscoveryStore.maxApiKeyBytes + 1),
        },
      ),
    ];
    for (final response in responses) {
      expect(response.statusCode, 400);
      expect(
        (response.json['error'] as Map<String, dynamic>)['code'],
        'INVALID_MUSIC_DISCOVERY_CONFIG',
      );
    }
  });

  test('owner deletion removes the shared key without affecting access',
      () async {
    await _request(
      port,
      'PUT',
      '/api/music-discovery/config',
      token: adminToken,
      body: <String, dynamic>{'lastFmApiKey': 'shared-key'},
    );
    final deleted = await _request(
      port,
      'DELETE',
      '/api/music-discovery/config',
      token: adminToken,
    );
    expect(deleted.statusCode, 200);
    expect(deleted.json['lastFmApiKey'], isNull);
    expect(deleted.json['canManage'], isTrue);

    final fetched = await _request(
      port,
      'GET',
      '/api/music-discovery/config',
      token: memberToken,
    );
    expect(fetched.statusCode, 200);
    expect(fetched.json['lastFmApiKey'], isNull);
  });

  test('shared key survives auth reinitialization in the same directory',
      () async {
    await _request(
      port,
      'PUT',
      '/api/music-discovery/config',
      token: adminToken,
      body: <String, dynamic>{'lastFmApiKey': 'durable-key'},
    );
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    await AuthService().register('owner2', 'owner2-pass-123456');
    final token =
        await _login(port, 'owner2', 'owner2-pass-123456', 'device-o2');
    final fetched = await _request(
      port,
      'GET',
      '/api/music-discovery/config',
      token: token,
    );
    expect(fetched.json['lastFmApiKey'], 'durable-key');
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
    body: <String, dynamic>{
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceId,
    },
  );
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
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    return _Response(
      response.statusCode,
      decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{},
    );
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response(this.statusCode, this.json);

  final int statusCode;
  final Map<String, dynamic> json;
}
