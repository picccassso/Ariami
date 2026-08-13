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
    directory = await Directory.systemTemp.createTemp('ariami_http_hidden_');
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

  test('hides one target and names it from the catalog', () async {
    final hidden = await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {'type': 'album', 'targetId': 'album-a'},
    );
    expect(hidden.statusCode, 200);

    final list = await _request(port, 'GET', '/api/hidden', token: userAToken);
    final items = list.json['hidden'] as List<dynamic>;
    expect(list.json['schemaVersion'], 1);
    expect(items, hasLength(1));
    expect((items.single as Map)['name'], 'Album A');
    expect((items.single as Map)['subtitle'], 'Artist A');
    expect((items.single as Map)['missing'], isFalse);
  });

  test('hides a whole selection in one request, skipping invalid rows',
      () async {
    final response = await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {
        'items': [
          {'type': 'album', 'targetId': 'album-a'},
          {'type': 'playlist', 'targetId': 'playlist-a'},
          {'type': 'artist', 'targetId': 'Kanye West'},
          {'type': 'song', 'targetId': 'song-a'},
        ],
      },
    );

    expect(response.statusCode, 200);
    expect((response.json['hidden'] as List), hasLength(3));
    expect(response.json['skipped'], 1);

    final list = await _request(port, 'GET', '/api/hidden', token: userAToken);
    final items = (list.json['hidden'] as List<dynamic>).cast<Map>();
    expect(
      items.map((item) => '${item['type']}:${item['targetId']}'),
      <String>['album:album-a', 'playlist:playlist-a', 'artist:Kanye West'],
      reason: 'a batch keeps the order it was sent in',
    );
    // An artist is a credit string, so its own name is the display name.
    expect(items.last['name'], 'Kanye West');
    expect(items[1]['subtitle'], '2 songs');
  });

  test('hidden items are per-account and unhide only affects the caller',
      () async {
    for (final token in <String>[userAToken, userBToken]) {
      await _request(
        port,
        'POST',
        '/api/hidden',
        token: token,
        body: {'type': 'album', 'targetId': 'album-a'},
      );
    }

    final removed = await _request(
      port,
      'DELETE',
      '/api/hidden/album/album-a',
      token: userAToken,
    );
    expect(removed.json['removed'], isTrue);

    final listA = await _request(port, 'GET', '/api/hidden', token: userAToken);
    final listB = await _request(port, 'GET', '/api/hidden', token: userBToken);
    expect(listA.json['hidden'], isEmpty);
    expect(listB.json['hidden'], hasLength(1));
  });

  test('a body cannot select another account', () async {
    await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {
        'type': 'album',
        'targetId': 'album-a',
        'userId': 'attempted-spoof',
      },
    );

    final listB = await _request(port, 'GET', '/api/hidden', token: userBToken);
    expect(listB.json['hidden'], isEmpty);
  });

  test('an artist name round-trips through the delete path', () async {
    await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {'type': 'artist', 'targetId': 'AC/DC & Friends'},
    );

    final removed = await _request(
      port,
      'DELETE',
      '/api/hidden/artist/${Uri.encodeComponent('AC/DC & Friends')}',
      token: userAToken,
    );

    expect(removed.json['removed'], isTrue);
    final list = await _request(port, 'GET', '/api/hidden', token: userAToken);
    expect(list.json['hidden'], isEmpty);
  });

  test('a target that left the library is still listed and nameable', () async {
    await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {'type': 'album', 'targetId': 'album-gone'},
    );

    final list = await _request(port, 'GET', '/api/hidden', token: userAToken);
    final item = (list.json['hidden'] as List).single as Map;
    expect(item['name'], 'Unavailable album');
    expect(item['missing'], isTrue);
  });

  test('invalid requests are rejected', () async {
    final badType = await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {'type': 'song', 'targetId': 'song-a'},
    );
    final blankTarget = await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {'type': 'album', 'targetId': '   '},
    );
    final emptyBatch = await _request(
      port,
      'POST',
      '/api/hidden',
      token: userAToken,
      body: {'items': <dynamic>[]},
    );

    expect(badType.statusCode, 400);
    expect(blankTarget.statusCode, 400);
    expect(emptyBatch.statusCode, 400);
    expect(
      (badType.json['error'] as Map)['code'],
      'INVALID_HIDDEN_ITEM',
    );
  });

  test('the endpoints require a session', () async {
    final list = await _request(port, 'GET', '/api/hidden');
    expect(list.statusCode, greaterThanOrEqualTo(400));
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
