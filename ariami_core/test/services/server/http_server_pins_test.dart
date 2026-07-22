import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  late AriamiHttpServer server;
  late Directory directory;
  late int port;
  late String userAToken;
  late String userBToken;

  setUp(() async {
    server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    directory = await Directory.systemTemp.createTemp('ariami_http_pins_');
    server.libraryManager
        .setCachePath(p.join(directory.path, 'metadata_cache.json'));
    server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    await AuthService().register('user-a', 'pass-a-123456');
    await AuthService().register('user-b', 'pass-b-123456');
    _seedCatalog(server.libraryManager.createCatalogRepository()!);
    port = await startHttpTestServer(server);
    userAToken = await _login(port, 'user-a', 'pass-a-123456', 'device-a');
    userBToken = await _login(port, 'user-b', 'pass-b-123456', 'device-b');
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  test('list, pin album, pin playlist, and duplicate is idempotent', () async {
    final album = await _request(
      port,
      'POST',
      '/api/pins',
      token: userAToken,
      body: {'type': 'album', 'targetId': 'album-a'},
    );
    final playlist = await _request(
      port,
      'POST',
      '/api/pins',
      token: userAToken,
      body: {'type': 'playlist', 'targetId': 'playlist-a'},
    );
    final duplicate = await _request(
      port,
      'POST',
      '/api/pins',
      token: userAToken,
      body: {
        'type': 'album',
        'targetId': 'album-a',
        'userId': 'attempted-spoof',
      },
    );

    expect(album.statusCode, 200);
    expect((album.json['pin'] as Map)['sortOrder'], 0);
    expect((playlist.json['pin'] as Map)['sortOrder'], 1);
    expect(duplicate.json['created'], isFalse);

    final list = await _request(
      port,
      'GET',
      '/api/pins',
      token: userAToken,
    );
    final pins = list.json['pins'] as List<dynamic>;
    expect(pins, hasLength(2));
    expect((pins.first as Map)['title'], 'Album A');
    expect((pins.last as Map)['name'], 'Playlist A');
  });

  test('pins are isolated and unpin removes only the session user', () async {
    for (final token in <String>[userAToken, userBToken]) {
      await _request(
        port,
        'POST',
        '/api/pins',
        token: token,
        body: {'type': 'album', 'targetId': 'album-a'},
      );
    }
    await _request(
      port,
      'DELETE',
      '/api/pins/album/album-a',
      token: userAToken,
    );

    final a = await _request(port, 'GET', '/api/pins', token: userAToken);
    final b = await _request(port, 'GET', '/api/pins', token: userBToken);
    expect(a.json['pins'], isEmpty);
    expect(b.json['pins'], hasLength(1));
  });

  test('invalid type is rejected and missing target resolves safely', () async {
    final invalid = await _request(
      port,
      'POST',
      '/api/pins',
      token: userAToken,
      body: {'type': 'song', 'targetId': 'song-a'},
    );
    expect(invalid.statusCode, 400);

    await _request(
      port,
      'POST',
      '/api/pins',
      token: userAToken,
      body: {'type': 'album', 'targetId': 'deleted-album'},
    );
    final list = await _request(port, 'GET', '/api/pins', token: userAToken);
    final missing = (list.json['pins'] as List<dynamic>).single as Map;
    expect(missing['missing'], isTrue);
    expect(missing['unavailable'], isTrue);
    expect(missing['title'], 'Unavailable album');
  });

  test('created playlist pins resolve from account playlist edits', () async {
    const playlistId = 'created:123-abc';
    final edit = await _request(
      port,
      'PUT',
      '/api/playlists/${Uri.encodeComponent(playlistId)}/edit',
      token: userAToken,
      body: {
        'name': 'Synced Mix',
        'songIds': <String>['song-a', 'song-b'],
        'baseSnapshot': <String>[],
      },
    );
    expect(edit.statusCode, 200);
    expect((edit.json['edit'] as Map)['playlistId'], playlistId);

    final pinned = await _request(
      port,
      'POST',
      '/api/pins',
      token: userAToken,
      body: {'type': 'playlist', 'targetId': playlistId},
    );
    expect(pinned.statusCode, 200);

    final list = await _request(port, 'GET', '/api/pins', token: userAToken);
    final created = (list.json['pins'] as List<dynamic>).single as Map;

    expect(created['type'], 'playlist');
    expect(created['targetId'], playlistId);
    expect(created['title'], 'Synced Mix');
    expect(created['name'], 'Synced Mix');
    expect(created['subtitle'], '2 songs');
    expect(created['missing'], isFalse);
    expect(created['unavailable'], isFalse);

    final removed = await _request(
      port,
      'DELETE',
      '/api/pins/playlist/${Uri.encodeComponent(playlistId)}',
      token: userAToken,
    );
    expect(removed.statusCode, 200);
    expect(removed.json['removed'], isTrue);

    final afterDelete =
        await _request(port, 'GET', '/api/pins', token: userAToken);
    expect(afterDelete.json['pins'], isEmpty);
  });

  test('export shape and repeated JSON import preserve pins without duplicates',
      () async {
    final backupPins = <Map<String, dynamic>>[
      {'type': 'playlist', 'targetId': 'playlist-a', 'sortOrder': 5},
      {'type': 'album', 'targetId': 'album-a', 'sortOrder': 2},
    ];
    for (var i = 0; i < 2; i++) {
      final imported = await _request(
        port,
        'POST',
        '/api/pins/import',
        token: userAToken,
        body: {'pins': backupPins, 'replace': false},
      );
      expect(imported.statusCode, 200);
      expect(imported.json['schemaVersion'], 1);
    }

    final exported =
        await _request(port, 'GET', '/api/pins', token: userAToken);
    final pins = exported.json['pins'] as List<dynamic>;
    expect(exported.json['schemaVersion'], 1);
    expect(pins, hasLength(2));
    expect(pins.map((pin) => (pin as Map)['sortOrder']), <int>[2, 5]);
  });
}

void _seedCatalog(CatalogRepository repository) {
  repository.upsertAlbum(CatalogAlbumRecord(
    id: 'album-a',
    title: 'Album A',
    artist: 'Artist A',
    coverArtKey: 'album-a',
    songCount: 1,
    durationSeconds: 120,
    updatedToken: 1,
  ));
  repository.upsertPlaylist(CatalogPlaylistRecord(
    id: 'playlist-a',
    name: 'Playlist A',
    songCount: 2,
    durationSeconds: 240,
    updatedToken: 2,
  ));
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

class _Response {
  const _Response(this.statusCode, this.json);
  final int statusCode;
  final Map<String, dynamic> json;
}
