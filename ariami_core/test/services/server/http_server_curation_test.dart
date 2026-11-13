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
  late String ownerToken;
  late String memberToken;
  late String memberUserId;

  setUp(() async {
    server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    directory = await Directory.systemTemp.createTemp('ariami_http_curation_');
    server.libraryManager
        .setCachePath(p.join(directory.path, 'metadata_cache.json'));
    server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    await AuthService().register('owner', 'owner-pass-123456');
    final member = await AuthService().register('member', 'member-pass-123456');
    memberUserId = member.userId;
    _seedCatalog(server.libraryManager.createCatalogRepository()!);
    port = await startHttpTestServer(server);
    ownerToken = await _login(port, 'owner', 'owner-pass-123456', 'dev-owner');
    memberToken =
        await _login(port, 'member', 'member-pass-123456', 'dev-member');
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  test('owner defaults to onboarded full mode; member needs onboarding', () async {
    final ownerRes = await _request(port, 'GET', '/api/v2/curation', token: ownerToken);
    expect(ownerRes.statusCode, 200);
    expect(ownerRes.json['mode'], 'full');
    expect(ownerRes.json['onboardingCompleted'], isTrue);

    final memberRes =
        await _request(port, 'GET', '/api/v2/curation', token: memberToken);
    expect(memberRes.statusCode, 200);
    expect(memberRes.json['mode'], 'full');
    expect(memberRes.json['onboardingCompleted'], isFalse);
  });

  test('user can save curated mode & rules and fetch them back', () async {
    final putRes = await _request(
      port,
      'PUT',
      '/api/v2/curation',
      token: memberToken,
      body: {
        'mode': 'curated',
        'onboardingCompleted': true,
        'rules': [
          {
            'targetType': 'artist',
            'targetId': 'Daft Punk',
            'action': 'include',
          },
          {
            'targetType': 'album',
            'targetId': 'alb-extra',
            'action': 'include',
          },
        ],
      },
    );
    expect(putRes.statusCode, 200);
    expect(putRes.json['mode'], 'curated');
    expect(putRes.json['onboardingCompleted'], isTrue);
    expect(putRes.json['revision'], 1);
    expect((putRes.json['rules'] as List), hasLength(2));

    final getRes =
        await _request(port, 'GET', '/api/v2/curation', token: memberToken);
    expect(getRes.statusCode, 200);
    expect(getRes.json['mode'], 'curated');
    expect((getRes.json['rules'] as List), hasLength(2));
  });

  test('admin can view and update a user curation and list catalog', () async {
    final forbidden = await _request(
      port,
      'GET',
      '/api/admin/users/$memberUserId/curation',
      token: memberToken,
    );
    expect(forbidden.statusCode, 403);

    final catalogRes = await _request(
      port,
      'GET',
      '/api/admin/curation/catalog',
      token: ownerToken,
    );
    expect(catalogRes.statusCode, 200);
    expect((catalogRes.json['albums'] as List), hasLength(2));
    expect((catalogRes.json['playlists'] as List), hasLength(1));
    expect((catalogRes.json['standaloneSongs'] as List), hasLength(1));
    final catalogSongs =
        (catalogRes.json['songs'] as List).cast<Map<String, dynamic>>();
    expect(catalogSongs, hasLength(2));
    final albumSong = catalogSongs.firstWhere((s) => s['id'] == 'song-1');
    expect(albumSong['albumId'], 'alb-dp');
    expect(albumSong['albumTitle'], 'Discovery');

    final songsSearch = await _request(
      port,
      'GET',
      '/api/admin/curation/songs?q=discovery',
      token: ownerToken,
    );
    expect(songsSearch.statusCode, 200);
    expect((songsSearch.json['songs'] as List), hasLength(1));

    final adminPut = await _request(
      port,
      'PUT',
      '/api/admin/users/$memberUserId/curation',
      token: ownerToken,
      body: {
        'mode': 'curated',
        'onboardingCompleted': true,
        'rules': [
          {
            'targetType': 'artist',
            'targetId': 'Daft Punk',
            'action': 'include',
          },
        ],
      },
    );
    expect(adminPut.statusCode, 200);

    final memberGet =
        await _request(port, 'GET', '/api/v2/curation', token: memberToken);
    expect(memberGet.json['mode'], 'curated');
    expect(memberGet.json['onboardingCompleted'], isTrue);

    final adminUsers =
        await _request(port, 'GET', '/api/admin/users', token: ownerToken);
    expect(adminUsers.statusCode, 200);
    final users = (adminUsers.json['users'] as List).cast<Map<String, dynamic>>();
    final memberRow = users.firstWhere((u) => u['userId'] == memberUserId);
    expect((memberRow['curation'] as Map)['mode'], 'curated');
    expect((memberRow['curation'] as Map)['includedArtists'], 1);
  });

  test('/api/hidden POST and DELETE stay synchronized with curation exclude rules',
      () async {
    final hideRes = await _request(
      port,
      'POST',
      '/api/hidden',
      token: memberToken,
      body: {'type': 'album', 'targetId': 'alb-dp'},
    );
    expect(hideRes.statusCode, 200);

    final curationAfterHide =
        await _request(port, 'GET', '/api/v2/curation', token: memberToken);
    final rulesAfterHide =
        (curationAfterHide.json['rules'] as List).cast<Map<String, dynamic>>();
    expect(rulesAfterHide, hasLength(1));
    expect(rulesAfterHide.single['action'], 'exclude');
    expect(rulesAfterHide.single['targetType'], 'album');
    expect(rulesAfterHide.single['targetId'], 'alb-dp');

    final unhideRes = await _request(
      port,
      'DELETE',
      '/api/hidden/album/alb-dp',
      token: memberToken,
    );
    expect(unhideRes.statusCode, 200);
    expect(unhideRes.json['removed'], isTrue);

    final curationAfterUnhide =
        await _request(port, 'GET', '/api/v2/curation', token: memberToken);
    expect(curationAfterUnhide.json['rules'], isEmpty);
  });
}

void _seedCatalog(CatalogRepository repository) {
  repository.upsertAlbum(CatalogAlbumRecord(
    id: 'alb-dp',
    title: 'Discovery',
    artist: 'Daft Punk',
    songCount: 1,
    durationSeconds: 320,
    updatedToken: 1,
  ));
  repository.upsertAlbum(CatalogAlbumRecord(
    id: 'alb-extra',
    title: 'Random Access Memories',
    artist: 'Daft Punk',
    songCount: 1,
    durationSeconds: 369,
    updatedToken: 2,
  ));
  repository.upsertSong(CatalogSongRecord(
    id: 'song-1',
    filePath: '/music/dp/one_more_time.flac',
    title: 'One More Time',
    artist: 'Daft Punk',
    albumId: 'alb-dp',
    durationSeconds: 320,
    updatedToken: 3,
  ));
  repository.upsertSong(CatalogSongRecord(
    id: 'song-solo',
    filePath: '/music/solo.flac',
    title: 'Loose Single',
    artist: 'Jamie xx',
    albumId: null,
    durationSeconds: 210,
    updatedToken: 4,
  ));
  repository.upsertPlaylist(CatalogPlaylistRecord(
    id: 'pl-1',
    name: 'Weekend Mix',
    songCount: 2,
    durationSeconds: 530,
    updatedToken: 5,
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
