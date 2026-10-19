import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  group('HTTP Server GET /api/lyrics/<songId>', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late String baseUrl;
    late String token;
    late File audioFile;
    late File lrcFile;

    Future<(int, Map<String, dynamic>)> getLyrics(
      String songId, {
      bool authorized = true,
    }) async {
      final client = HttpClient();
      try {
        final request =
            await client.getUrl(Uri.parse('$baseUrl/api/lyrics/$songId'));
        if (authorized) {
          request.headers.set('Authorization', 'Bearer $token');
        }
        final response = await request.close();
        final text = await utf8.decodeStream(response);
        Map<String, dynamic> body = <String, dynamic>{};
        try {
          if (text.isNotEmpty) {
            body = jsonDecode(text) as Map<String, dynamic>;
          }
        } catch (_) {}
        return (
          response.statusCode,
          body,
        );
      } finally {
        client.close(force: true);
      }
    }

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      testDir = await Directory.systemTemp.createTemp('ariami_lyrics_http_');

      audioFile = File(p.join(testDir.path, 'song1.mp3'));
      await audioFile.writeAsString('audio content');
      lrcFile = File(p.join(testDir.path, 'song1.lrc'));
      await lrcFile.writeAsString('[00:10.00]Hello world\n[00:20.00]Second line');

      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
      server.setMusicFolderPath(testDir.path);
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );

      final repo = server.libraryManager.createCatalogRepository()!;
      repo.upsertSong(
        CatalogSongRecord(
          id: 'song-1',
          filePath: audioFile.path,
          title: 'Song 1',
          artist: 'Artist 1',
          durationSeconds: 120,
          updatedToken: 1,
          hasLyrics: true,
        ),
      );

      final boundPort = await startHttpTestServer(server);
      baseUrl = 'http://127.0.0.1:$boundPort';

      final client = HttpClient();
      try {
        final regReq =
            await client.postUrl(Uri.parse('$baseUrl/api/auth/register'));
        regReq.headers.set('Content-Type', 'application/json');
        regReq.write(
            jsonEncode({'username': 'alice', 'password': 'password123'}));
        final regRes = await regReq.close();
        await utf8.decodeStream(regRes);

        final loginReq =
            await client.postUrl(Uri.parse('$baseUrl/api/auth/login'));
        loginReq.headers.set('Content-Type', 'application/json');
        loginReq.write(jsonEncode({
          'username': 'alice',
          'password': 'password123',
          'deviceId': 'test-phone',
          'deviceName': 'Alice Phone',
        }));
        final loginRes = await loginReq.close();
        final loginText = await utf8.decodeStream(loginRes);
        final loginJson = jsonDecode(loginText) as Map<String, dynamic>;
        token = loginJson['sessionToken'] as String;
      } finally {
        client.close(force: true);
      }
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('returns 200 with parsed lyrics when lyrics file exists', () async {
      final (status, json) = await getLyrics('song-1');
      expect(status, 200);
      expect(json['songId'], 'song-1');
      expect(json['type'], 'synced');
      expect(json['lines'], isA<List>());
      final lines = json['lines'] as List;
      expect(lines.length, 2);
      expect(lines[0]['text'], 'Hello world');
      expect(lines[0]['timestampMs'], 10000);
      expect(lines[1]['text'], 'Second line');
      expect(lines[1]['timestampMs'], 20000);
    });

    test('returns 404 when song or lyrics do not exist', () async {
      final (status, _) = await getLyrics('non-existent-song');
      expect(status, 404);
    });
  });
}
