import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  group('music folder setup endpoints', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late Directory musicDir;
    String? savedPath;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      savedPath = null;

      testDir =
          await Directory.systemTemp.createTemp('ariami_music_setup_api_');
      musicDir = Directory(p.join(testDir.path, 'music'));
      await musicDir.create(recursive: true);

      server.setSetupCallbacks(
        getConfiguredMusicFolderPath: () async => savedPath,
        setMusicFolder: (path) async {
          savedPath = path;
          return true;
        },
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('GET suggestions includes configured path validation', () async {
      savedPath = musicDir.path;
      final port = await startHttpTestServer(server);

      final response = await _getJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder/suggestions'),
      );

      expect(response.statusCode, 200);
      final suggestions = response.body['suggestions'] as List<dynamic>;
      expect(suggestions, isNotEmpty);
      expect(
        suggestions.first,
        predicate<Map<String, dynamic>>(
          (item) =>
              item['path'] == musicDir.path &&
              item['exists'] == true &&
              item['readable'] == true &&
              item['isValid'] == true,
        ),
      );
    });

    test('POST validate returns missing vs readable results', () async {
      final port = await startHttpTestServer(server);

      final valid = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder/validate'),
        {'path': musicDir.path},
      );
      expect(valid.statusCode, 200);
      expect(valid.body['success'], isTrue);
      expect(valid.body['validation']['isValid'], isTrue);

      final missing = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder/validate'),
        {'path': p.join(testDir.path, 'missing')},
      );
      expect(missing.statusCode, 200);
      expect(missing.body['success'], isFalse);
      expect(missing.body['validation']['error'], 'missing');
    });

    test('POST set rejects invalid path with validation details', () async {
      final port = await startHttpTestServer(server);

      final response = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder'),
        {'path': p.join(testDir.path, 'missing')},
      );

      expect(response.statusCode, 200);
      expect(response.body['success'], isFalse);
      expect(response.body['error'], 'missing');
      expect(savedPath, isNull);
    });

    test('POST set saves valid path', () async {
      final port = await startHttpTestServer(server);

      final response = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder'),
        {'path': musicDir.path},
      );

      expect(response.statusCode, 200);
      expect(response.body['success'], isTrue);
      expect(response.body['path'], musicDir.path);
      expect(response.body['validation'], isA<Map<String, dynamic>>());
      expect(response.body['validation']['path'], musicDir.path);
      expect(response.body['validation']['isValid'], isTrue);
      expect(savedPath, musicDir.path);
    });

    test('POST set requires admin auth after owner exists', () async {
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );

      final port = await startHttpTestServer(server);

      final register = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        {'username': 'owner', 'password': 'owner-pass'},
      );
      expect(register.statusCode, 200);

      final missingAuth = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder'),
        {'path': musicDir.path},
      );
      expect(missingAuth.statusCode, 401);

      final login = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        {
          'username': 'owner',
          'password': 'owner-pass',
          'deviceId': 'owner-device',
          'deviceName': 'Owner Device',
        },
      );
      expect(login.statusCode, 200);
      final token = login.body['sessionToken'] as String;

      final authorized = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/music-folder'),
        {'path': musicDir.path},
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(authorized.statusCode, 200);
      expect(authorized.body['success'], isTrue);
      expect(savedPath, musicDir.path);
    });
  });
}

Future<({int statusCode, Map<String, dynamic> body})> _getJson(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final bodyText = await response.transform(utf8.decoder).join();
    return (
      statusCode: response.statusCode,
      body: jsonDecode(bodyText) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

Future<({int statusCode, Map<String, dynamic> body})> _postJson(
  Uri url,
  Map<String, dynamic> payload, {
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    headers?.forEach(request.headers.set);
    request.write(jsonEncode(payload));
    final response = await request.close();
    final bodyText = await response.transform(utf8.decoder).join();
    return (
      statusCode: response.statusCode,
      body: jsonDecode(bodyText) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}
