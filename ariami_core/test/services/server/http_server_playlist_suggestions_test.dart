import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Playlist-suggestion approval endpoints: decisions persist through the
/// LibraryManager decision store, hide suggestions immediately, and imports
/// trigger a rescan. Both endpoints are library-wide, so they authorize like
/// the other setup endpoints (open in legacy mode, admin once users exist).
void main() {
  group('playlist suggestion endpoints (legacy mode)', () {
    late AriamiHttpServer server;
    late Directory directory;
    late Directory musicDir;
    late String suggestibleFolderPath;
    late int port;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      directory =
          await Directory.systemTemp.createTemp('ariami_suggestions_api_');
      server.libraryManager.setCachePath(
        p.join(directory.path, 'config', 'metadata_cache.json'),
      );

      musicDir = Directory(p.join(directory.path, 'music'));
      suggestibleFolderPath = p.join(musicDir.path, 'Party Mix');
      for (var i = 1; i <= 5; i++) {
        await _writeTaggedAudio(
          p.join(suggestibleFolderPath, 'song $i.mp3'),
          fillByte: i,
          title: 'Song $i',
          artist: 'Artist $i',
          album: 'Album $i',
        );
      }

      port = await _freePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );
    });

    tearDown(() async {
      server.setSetupCallbacks(); // clear callbacks on the singleton
      await server.stop();
      server.libraryManager.clear();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('ignore hides a scanned suggestion; reset re-surfaces it', () async {
      await server.libraryManager.scanMusicFolder(musicDir.path);

      final initial =
          await _request(port, 'GET', '/api/playlists/suggestions');
      expect(initial.statusCode, 200);
      final suggestions = initial.json['suggestions'] as List<dynamic>;
      expect(
        suggestions.map((s) => (s as Map)['folderPath']),
        [suggestibleFolderPath],
      );

      final ignored = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'folderPath': suggestibleFolderPath, 'decision': 'ignore'},
      );
      expect(ignored.statusCode, 200);
      expect(ignored.json['success'], isTrue);

      final afterIgnore =
          await _request(port, 'GET', '/api/playlists/suggestions');
      expect(afterIgnore.json['suggestions'], isEmpty,
          reason: 'a decision hides its suggestion without waiting for a '
              'rescan');
      final decisions = afterIgnore.json['decisions'] as List<dynamic>;
      expect((decisions.single as Map)['folderPath'], suggestibleFolderPath);
      expect((decisions.single as Map)['decision'], 'ignore');

      final reset = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'folderPath': suggestibleFolderPath, 'decision': 'reset'},
      );
      expect(reset.statusCode, 200);
      expect(reset.json['removed'], isTrue);

      final afterReset =
          await _request(port, 'GET', '/api/playlists/suggestions');
      expect(afterReset.json['suggestions'], hasLength(1));
      expect(afterReset.json['decisions'], isEmpty);
    });

    test('import records the decision and triggers the start-scan callback',
        () async {
      var scanRequested = false;
      server.setSetupCallbacks(
        startScan: () async {
          scanRequested = true;
          return true;
        },
      );

      final imported = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'folderPath': suggestibleFolderPath, 'decision': 'import'},
      );
      expect(imported.statusCode, 200);
      expect(imported.json['success'], isTrue);
      expect(imported.json['rescanStarted'], isTrue);
      expect(scanRequested, isTrue);

      final decisionStore = server.libraryManager.playlistDecisionStore!;
      expect(decisionStore.importedFolderPaths, {suggestibleFolderPath});
    });

    test('an imported folder becomes a playlist on the next scan', () async {
      await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'folderPath': suggestibleFolderPath, 'decision': 'import'},
      );
      await server.libraryManager.scanMusicFolder(musicDir.path);

      final playlists = server.libraryManager.library!.folderPlaylists;
      expect(playlists.single.name, 'Party Mix');
      expect(playlists.single.songIds, hasLength(5));
    });

    test('invalid decisions and folder paths are rejected', () async {
      final unknownDecision = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'folderPath': suggestibleFolderPath, 'decision': 'always'},
      );
      expect(unknownDecision.statusCode, 400);

      final relativePath = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'folderPath': 'relative/mix', 'decision': 'import'},
      );
      expect(relativePath.statusCode, 400);

      final missingPath = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: {'decision': 'import'},
      );
      expect(missingPath.statusCode, 400);

      final notJson = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        rawBody: 'not json',
      );
      expect(notJson.statusCode, 400);
    });
  });

  group('playlist suggestion endpoints (auth required)', () {
    late AriamiHttpServer server;
    late Directory directory;
    late int port;
    late String ownerToken;
    late String memberToken;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      directory =
          await Directory.systemTemp.createTemp('ariami_suggestions_auth_');
      server.libraryManager.setCachePath(
        p.join(directory.path, 'config', 'metadata_cache.json'),
      );
      await server.initializeAuth(
        usersFilePath: p.join(directory.path, 'users.json'),
        sessionsFilePath: p.join(directory.path, 'sessions.json'),
        forceReinitialize: true,
      );
      // The first registered user is the admin/owner.
      await AuthService().register('owner', 'owner-pass');
      await AuthService().register('member', 'member-pass');
      server.updateAuthMode();

      port = await _freePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );
      ownerToken = await _login(port, 'owner', 'owner-pass', 'device-owner');
      memberToken =
          await _login(port, 'member', 'member-pass', 'device-member');
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('requires an admin session once users exist', () async {
      final folderPath = p.join(directory.path, 'music', 'Party Mix');
      final body = {'folderPath': folderPath, 'decision': 'ignore'};

      final anonymous = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        body: body,
      );
      expect(anonymous.statusCode, 401);

      final member = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        token: memberToken,
        body: body,
      );
      expect(member.statusCode, 403);

      final owner = await _request(
        port,
        'POST',
        '/api/playlists/suggestions/decision',
        token: ownerToken,
        body: body,
      );
      expect(owner.statusCode, 200);
      expect(owner.json['success'], isTrue);

      final anonymousGet =
          await _request(port, 'GET', '/api/playlists/suggestions');
      expect(anonymousGet.statusCode, 401);

      final ownerGet = await _request(
        port,
        'GET',
        '/api/playlists/suggestions',
        token: ownerToken,
      );
      expect(ownerGet.statusCode, 200);
      expect(ownerGet.json['decisions'], hasLength(1));
    });
  });
}

/// Writes a small MP3-shaped file with a minimal ID3v1 tag trailer.
Future<void> _writeTaggedAudio(
  String filePath, {
  required int fillByte,
  required String title,
  required String artist,
  required String album,
}) async {
  List<int> fixedField(String value, int length) {
    final bytes = ascii.encode(value);
    return [
      ...bytes.take(length),
      ...List<int>.filled(length - min(bytes.length, length), 0),
    ];
  }

  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes([
    ...List<int>.filled(4096, fillByte),
    ...ascii.encode('TAG'),
    ...fixedField(title, 30),
    ...fixedField(artist, 30),
    ...fixedField(album, 30),
    ...ascii.encode('2024'),
    ...List<int>.filled(30, 0), // comment
    255, // genre: none
  ]);
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
  String? rawBody,
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
    if (body != null || rawBody != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(rawBody ?? jsonEncode(body));
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
