import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/library/library_upload_paths.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  group('resolveLibraryUploadTarget', () {
    const root = '/srv/music';

    test('joins folder and nested path under the root', () {
      expect(resolveLibraryUploadTarget(root, 'Mix', 'Artist/Album/01.flac'),
          p.join(root, 'Mix', 'Artist', 'Album', '01.flac'));
      expect(resolveLibraryUploadTarget(root, '', 'song.MP3'),
          p.join(root, 'song.MP3'));
    });

    test('rejects escapes, hidden segments and other file types', () {
      for (final (folder, path) in [
        ('..', 'song.mp3'),
        ('', '../song.mp3'),
        ('Mix', 'a/../../song.mp3'),
        ('.hidden', 'song.mp3'),
        ('', r'a\..\song.mp3'),
        ('', 'notes.nfo'),
        ('Mix', ''),
      ]) {
        expect(resolveLibraryUploadTarget(root, folder, path), isNull,
            reason: '$folder | $path');
      }
    });
  });

  group('library upload endpoints', () {
    late AriamiHttpServer server;
    late Directory directory;
    late Directory music;
    late int port;
    late String adminToken;
    late String memberToken;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      directory = await Directory.systemTemp.createTemp('ariami_http_upload_');
      music = await Directory(p.join(directory.path, 'music')).create();
      await Directory(p.join(music.path, 'Playlists', 'Gym'))
          .create(recursive: true);
      await Directory(p.join(music.path, '.cache')).create();
      server.libraryManager
          .setCachePath(p.join(directory.path, 'metadata_cache.json'));
      // Hosts set the folder by scanning it, not via setMusicFolderPath.
      await server.libraryManager.scanMusicFolder(music.path);
      await server.initializeAuth(
        usersFilePath: p.join(directory.path, 'users.json'),
        sessionsFilePath: p.join(directory.path, 'sessions.json'),
        forceReinitialize: true,
      );
      await AuthService().register('owner', 'owner-pass-123456');
      await AuthService().register('member', 'member-pass-123456');
      port = await startHttpTestServer(server);
      adminToken = await _login(port, 'owner', 'owner-pass-123456');
      memberToken = await _login(port, 'member', 'member-pass-123456');
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      await directory.delete(recursive: true);
    });

    test('lists visible folders and accepted file types', () async {
      final response =
          await _send(port, 'GET', '/api/admin/library/folders', adminToken);
      expect(response.statusCode, 200);
      expect(response.json['folders'], ['Playlists', 'Playlists/Gym']);
      expect(response.json['allowedExtensions'], contains('.flac'));
    });

    test('streams a file into the chosen folder, creating subfolders',
        () async {
      final response = await _send(
          port,
          'POST',
          '/api/admin/library/upload?folder=Playlists/Gym&path=New/01.mp3',
          adminToken,
          body: [1, 2, 3]);
      expect(response.statusCode, 200);
      expect(response.json['path'], 'Playlists/Gym/New/01.mp3');
      final written =
          File(p.join(music.path, 'Playlists', 'Gym', 'New', '01.mp3'));
      expect(await written.readAsBytes(), [1, 2, 3]);
      expect(
          written.parent.listSync().map((e) => p.basename(e.path)), ['01.mp3']);
    });

    test('never overwrites an existing file', () async {
      final existing = File(p.join(music.path, 'song.mp3'))
        ..writeAsBytesSync([9]);
      final response = await _send(
          port, 'POST', '/api/admin/library/upload?path=song.mp3', adminToken,
          body: [1]);
      expect(response.statusCode, 409);
      expect(existing.readAsBytesSync(), [9]);
    });

    test('rejects paths outside the library and unsupported types', () async {
      for (final query in [
        'path=../x.mp3',
        'folder=..&path=x.mp3',
        'path=x.exe'
      ]) {
        final response = await _send(
            port, 'POST', '/api/admin/library/upload?$query', adminToken,
            body: [1]);
        expect(response.statusCode, 400, reason: query);
      }
      expect(File(p.join(directory.path, 'x.mp3')).existsSync(), isFalse);
    });

    test('is owner only', () async {
      final folders =
          await _send(port, 'GET', '/api/admin/library/folders', memberToken);
      final upload = await _send(
          port, 'POST', '/api/admin/library/upload?path=x.mp3', memberToken,
          body: [1]);
      expect(folders.statusCode, 403);
      expect(upload.statusCode, 403);
      expect(File(p.join(music.path, 'x.mp3')).existsSync(), isFalse);
    });

    test('accepts bodies past the default request size limit', () async {
      final big = List<int>.filled(3 * 1024 * 1024, 7);
      final response = await _send(
          port, 'POST', '/api/admin/library/upload?path=big.flac', adminToken,
          body: big);
      expect(response.statusCode, 200);
      expect(File(p.join(music.path, 'big.flac')).lengthSync(), big.length);
    });
  });
}

Future<String> _login(int port, String username, String password) async {
  final response = await _send(port, 'POST', '/api/auth/login', null,
      body: utf8.encode(jsonEncode({
        'username': username,
        'password': password,
        'deviceId': 'device-$username',
        'deviceName': username,
      })),
      contentType: 'application/json');
  expect(response.statusCode, 200);
  return response.json['sessionToken'] as String;
}

Future<({int statusCode, Map<String, dynamic> json})> _send(
  int port,
  String method,
  String path,
  String? token, {
  List<int>? body,
  String contentType = 'application/octet-stream',
}) async {
  final client = HttpClient();
  try {
    final request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.add(body);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (
      statusCode: response.statusCode,
      json: text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}
