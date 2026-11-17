import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('wishlist CRUD, Lidarr/text feed token auth, webhook, and auto-prune',
      () async {
    final webhookPayloads = <Map<String, dynamic>>[];
    final webhookReceived = Completer<void>();
    final webhookServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(webhookServer.forEach((req) async {
      final body = await utf8.decoder.bind(req).join();
      webhookPayloads.add(jsonDecode(body) as Map<String, dynamic>);
      req.response.statusCode = 200;
      await req.response.close();
      if (!webhookReceived.isCompleted) webhookReceived.complete();
    }));

    server.setMusicBrainzClientForTesting(
      MusicBrainzIdentityClient(
        requestSpacing: Duration.zero,
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'artists': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                  'name': 'Resolved Artist',
                  'score': 100,
                },
              ],
            }),
            200,
          );
        }),
      ),
    );

    try {
      await _request(
        port,
        'PUT',
        '/api/music-discovery/config',
        token: adminToken,
        body: <String, dynamic>{
          'webhookUrl': 'http://127.0.0.1:${webhookServer.port}/hook',
        },
      );

      final trackRec = MusicRecommendation(
        kind: MusicRecommendationKind.track,
        name: 'Wanted Song',
        artist: 'Resolved Artist',
        score: 0.9,
        lastFmUrl:
            Uri.https('www.last.fm', '/music/Resolved+Artist/_/Wanted+Song'),
        sourceSeeds: const <String>['Seed'],
      );
      final artistRec = MusicRecommendation(
        kind: MusicRecommendationKind.artist,
        name: 'Keep Artist',
        score: 0.8,
        lastFmUrl: Uri.https('www.last.fm', '/music/Keep+Artist'),
        musicBrainzId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        sourceSeeds: const <String>['Seed'],
      );

      final addedTrack = await _request(
        port,
        'POST',
        '/api/music-discovery/wishlist',
        token: memberToken,
        body: trackRec.toJson(),
      );
      expect(addedTrack.statusCode, 200);
      expect(
        (addedTrack.json['item'] as Map<String, dynamic>)['artistMusicBrainzId'],
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
      await webhookReceived.future.timeout(const Duration(seconds: 3));
      expect(webhookPayloads.single['event'], 'music_discovery.wishlist_added');

      await _request(
        port,
        'POST',
        '/api/music-discovery/wishlist',
        token: memberToken,
        body: artistRec.toJson(),
      );

      final feedToken = addedTrack.json['feedToken'] as String;
      final unauthFeed =
          await _requestRaw(port, '/api/music-discovery/wishlist/feed');
      expect(unauthFeed.statusCode, 401);

      final lidarrFeed = await _requestRaw(
        port,
        '/api/music-discovery/wishlist/feed?format=lidarr&token=$feedToken',
      );
      expect(lidarrFeed.statusCode, 200);
      final lidarrItems = jsonDecode(lidarrFeed.body) as List<dynamic>;
      expect(
        lidarrItems,
        <Map<String, dynamic>>[
          <String, dynamic>{
            'MusicBrainzId': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            'ArtistName': 'Keep Artist',
          },
          <String, dynamic>{
            'MusicBrainzId': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'ArtistName': 'Resolved Artist',
          },
        ],
      );

      final textFeed = await _requestRaw(
        port,
        '/api/music-discovery/wishlist/feed?format=text&token=$feedToken',
      );
      expect(textFeed.statusCode, 200);
      expect(textFeed.body, 'Keep Artist\nResolved Artist - Wanted Song');

      // Simulating library ingest removes the wishlisted track automatically.
      server.libraryManager.setLibraryForTesting(
        const LibraryStructure(
          albums: <String, Album>{},
          standaloneSongs: <SongMetadata>[
            SongMetadata(
              filePath: '/music/wanted.flac',
              title: 'Wanted Song',
              artist: 'Resolved Artist',
            ),
          ],
        ),
      );

      final afterIngest = await _request(
        port,
        'GET',
        '/api/music-discovery/wishlist',
        token: memberToken,
      );
      final remaining = (afterIngest.json['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(remaining.map((item) => item['name']), <String>['Keep Artist']);

      final deleted = await _request(
        port,
        'DELETE',
        '/api/music-discovery/wishlist?key=${Uri.encodeQueryComponent(artistRec.identityKey)}',
        token: memberToken,
      );
      expect(deleted.statusCode, 200);
      expect(deleted.json['items'], isEmpty);
    } finally {
      server.setMusicBrainzClientForTesting(null);
      await webhookServer.close(force: true);
    }
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

Future<({int statusCode, String body})> _requestRaw(
  int port,
  String path,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final response = await request.close();
    return (
      statusCode: response.statusCode,
      body: await utf8.decodeStream(response),
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
