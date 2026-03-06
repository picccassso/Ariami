import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Phase 4 - V2 HTTP endpoints and auth enforcement', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_phase4_');
      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('P4-1: v2 endpoints support legacy mode and pagination continuity',
        () async {
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );

      final repository = server.libraryManager.createCatalogRepository();
      expect(repository, isNotNull);
      _seedCatalog(repository!);

      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final albumsPage1 = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/v2/albums?limit=2'),
      );
      expect(albumsPage1.statusCode, 200);
      expect(albumsPage1.jsonBody['syncToken'], isA<int>());
      expect(
        _extractIds(albumsPage1.jsonBody['albums'] as List<dynamic>),
        equals(<String>['album-a', 'album-b']),
      );
      final pageInfo1 =
          albumsPage1.jsonBody['pageInfo'] as Map<String, dynamic>;
      expect(pageInfo1['hasMore'], isTrue);
      expect(pageInfo1['nextCursor'], equals('album-b'));

      final albumsPage2 = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse(
          'http://127.0.0.1:$port/api/v2/albums?limit=2&cursor=${Uri.encodeQueryComponent(pageInfo1['nextCursor'] as String)}',
        ),
      );
      expect(albumsPage2.statusCode, 200);
      expect(
        _extractIds(albumsPage2.jsonBody['albums'] as List<dynamic>),
        equals(<String>['album-c']),
      );
      final pageInfo2 =
          albumsPage2.jsonBody['pageInfo'] as Map<String, dynamic>;
      expect(pageInfo2['hasMore'], isFalse);
      expect(pageInfo2['nextCursor'], isNull);

      final bootstrapPage1 = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/v2/bootstrap?limit=2'),
      );
      expect(bootstrapPage1.statusCode, 200);
      expect(
        _extractIds(bootstrapPage1.jsonBody['albums'] as List<dynamic>),
        equals(<String>['album-a', 'album-b']),
      );
      expect(
        _extractIds(bootstrapPage1.jsonBody['songs'] as List<dynamic>),
        equals(<String>['song-a', 'song-b']),
      );
      final bootstrapInfo1 =
          bootstrapPage1.jsonBody['pageInfo'] as Map<String, dynamic>;
      expect(bootstrapInfo1['hasMore'], isTrue);
      expect(bootstrapInfo1['nextCursor'], isA<String>());

      final bootstrapPage2 = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse(
          'http://127.0.0.1:$port/api/v2/bootstrap?limit=2&cursor=${Uri.encodeQueryComponent(bootstrapInfo1['nextCursor'] as String)}',
        ),
      );
      expect(bootstrapPage2.statusCode, 200);
      expect(
        _extractIds(bootstrapPage2.jsonBody['albums'] as List<dynamic>),
        equals(<String>['album-c']),
      );
      expect(
        _extractIds(bootstrapPage2.jsonBody['songs'] as List<dynamic>),
        equals(<String>['song-c']),
      );

      final changesPage = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/v2/changes?since=0&limit=2'),
      );
      expect(changesPage.statusCode, 200);
      expect(changesPage.jsonBody['fromToken'], equals(0));
      expect(changesPage.jsonBody['events'], isA<List<dynamic>>());
      expect(changesPage.jsonBody['hasMore'], isTrue);
      expect(changesPage.jsonBody['syncToken'], isA<int>());
    });

    test(
        'P4-1: v2 endpoints enforce auth-required mode like protected v1 routes',
        () async {
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users_auth.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions_auth.json'),
        forceReinitialize: true,
      );

      final repository = server.libraryManager.createCatalogRepository();
      expect(repository, isNotNull);
      _seedCatalog(repository!);

      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'phase4-user',
          'password': 'phase4-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final unauthorizedV2 = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/v2/albums?limit=1'),
      );
      expect(unauthorizedV2.statusCode, 401);

      final loginResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'phase4-user',
          'password': 'phase4-pass',
          'deviceId': 'phase4-device',
          'deviceName': 'Phase 4 Device',
        },
      );
      expect(loginResponse.statusCode, 200);
      final token = loginResponse.jsonBody['sessionToken'] as String?;
      expect(token, isNotNull);

      final authorizedV2 = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/v2/albums?limit=1'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      expect(authorizedV2.statusCode, 200);
      expect(authorizedV2.jsonBody['albums'], isA<List<dynamic>>());
    });

    test(
      'P10-2: v2 and download-job endpoints require valid session with deterministic auth codes',
      () async {
        server.setFeatureFlags(
          const AriamiFeatureFlags(enableV2Api: true, enableDownloadJobs: true),
        );

        await server.initializeAuth(
          usersFilePath: p.join(testDir.path, 'users_p10_auth.json'),
          sessionsFilePath: p.join(testDir.path, 'sessions_p10_auth.json'),
          forceReinitialize: true,
        );

        final port = await _findFreePort();
        await server.start(
          advertisedIp: '127.0.0.1',
          bindAddress: '127.0.0.1',
          port: port,
        );

        final registerResponse = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
          jsonBody: <String, dynamic>{
            'username': 'phase10-auth-user',
            'password': 'phase10-auth-pass',
          },
        );
        expect(registerResponse.statusCode, 200);

        final missingAuthV2 = await _sendJsonRequest(
          method: 'GET',
          url: Uri.parse('http://127.0.0.1:$port/api/v2/albums?limit=1'),
        );
        expect(missingAuthV2.statusCode, 401);
        expect(
          (missingAuthV2.jsonBody['error'] as Map<String, dynamic>)['code'],
          AuthErrorCodes.authRequired,
        );

        final missingAuthJob = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/v2/download-jobs'),
          jsonBody: <String, dynamic>{
            'songIds': <String>['song-a'],
          },
        );
        expect(missingAuthJob.statusCode, 401);
        expect(
          (missingAuthJob.jsonBody['error'] as Map<String, dynamic>)['code'],
          AuthErrorCodes.authRequired,
        );

        const invalidAuthHeader = <String, String>{
          'Authorization': 'Bearer invalid-token',
        };

        final invalidSessionV2 = await _sendJsonRequest(
          method: 'GET',
          url: Uri.parse('http://127.0.0.1:$port/api/v2/albums?limit=1'),
          headers: invalidAuthHeader,
        );
        expect(invalidSessionV2.statusCode, 401);
        expect(
          (invalidSessionV2.jsonBody['error'] as Map<String, dynamic>)['code'],
          AuthErrorCodes.sessionExpired,
        );

        final invalidSessionJob = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/v2/download-jobs'),
          headers: invalidAuthHeader,
          jsonBody: <String, dynamic>{
            'songIds': <String>['song-a'],
          },
        );
        expect(invalidSessionJob.statusCode, 401);
        expect(
          (invalidSessionJob.jsonBody['error'] as Map<String, dynamic>)['code'],
          AuthErrorCodes.sessionExpired,
        );
      },
    );

    test(
      'P10-2: stream and download token-to-song validation remains unchanged',
      () async {
        await server.initializeAuth(
          usersFilePath: p.join(testDir.path, 'users_p10_tokens.json'),
          sessionsFilePath: p.join(testDir.path, 'sessions_p10_tokens.json'),
          forceReinitialize: true,
        );

        final port = await _findFreePort();
        await server.start(
          advertisedIp: '127.0.0.1',
          bindAddress: '127.0.0.1',
          port: port,
        );

        final registerResponse = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
          jsonBody: <String, dynamic>{
            'username': 'phase10-token-user',
            'password': 'phase10-token-pass',
          },
        );
        expect(registerResponse.statusCode, 200);

        final loginResponse = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
          jsonBody: <String, dynamic>{
            'username': 'phase10-token-user',
            'password': 'phase10-token-pass',
            'deviceId': 'phase10-device',
            'deviceName': 'Phase 10 Device',
          },
        );
        expect(loginResponse.statusCode, 200);
        final sessionToken = loginResponse.jsonBody['sessionToken'] as String?;
        expect(sessionToken, isNotNull);

        final ticketResponse = await _sendJsonRequest(
          method: 'POST',
          url: Uri.parse('http://127.0.0.1:$port/api/stream-ticket'),
          headers: <String, String>{'Authorization': 'Bearer $sessionToken'},
          jsonBody: <String, dynamic>{'songId': 'song-a'},
        );
        expect(ticketResponse.statusCode, 200);
        final streamToken = ticketResponse.jsonBody['streamToken'] as String?;
        expect(streamToken, isNotNull);

        final streamMismatch = await _sendJsonRequest(
          method: 'GET',
          url: Uri.parse(
            'http://127.0.0.1:$port/api/stream/song-b?streamToken=$streamToken',
          ),
        );
        expect(streamMismatch.statusCode, 403);
        expect(
          (streamMismatch.jsonBody['error'] as Map<String, dynamic>)['code'],
          AuthErrorCodes.streamTokenExpired,
        );
        expect(
          (streamMismatch.jsonBody['error'] as Map<String, dynamic>)['message'],
          contains('does not match requested song'),
        );

        final downloadMismatch = await _sendJsonRequest(
          method: 'GET',
          url: Uri.parse(
            'http://127.0.0.1:$port/api/download/song-b?streamToken=$streamToken',
          ),
        );
        expect(downloadMismatch.statusCode, 403);
        expect(
          (downloadMismatch.jsonBody['error'] as Map<String, dynamic>)['code'],
          AuthErrorCodes.streamTokenExpired,
        );
        expect(
          (downloadMismatch.jsonBody['error']
              as Map<String, dynamic>)['message'],
          contains('does not match requested song'),
        );
      },
    );

    test(
      'P4-2: scan completion broadcasts both library_updated and sync_token_advanced',
      () async {
        await server.initializeAuth(
          usersFilePath: p.join(testDir.path, 'users_ws.json'),
          sessionsFilePath: p.join(testDir.path, 'sessions_ws.json'),
          forceReinitialize: true,
        );

        final musicDir =
            await Directory(p.join(testDir.path, 'music')).create();
        await _writeAudioStub(
            p.join(musicDir.path, 'Phase4 Artist - Track.mp3'));

        final port = await _findFreePort();
        await server.start(
          advertisedIp: '127.0.0.1',
          bindAddress: '127.0.0.1',
          port: port,
        );

        final webSocket =
            await WebSocket.connect('ws://127.0.0.1:$port/api/ws');

        final completer = Completer<void>();
        Map<String, dynamic>? libraryUpdated;
        Map<String, dynamic>? syncTokenAdvanced;
        late final StreamSubscription<dynamic> subscription;
        subscription = webSocket.listen((raw) {
          if (raw is! String) {
            return;
          }

          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final type = decoded['type'] as String?;
          if (type == 'library_updated' && libraryUpdated == null) {
            libraryUpdated = decoded;
          }
          if (type == 'sync_token_advanced' && syncTokenAdvanced == null) {
            syncTokenAdvanced = decoded;
          }
          if (libraryUpdated != null && syncTokenAdvanced != null) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        });

        webSocket.add(
          jsonEncode({
            'type': 'identify',
            'data': {
              'deviceId': 'phase4-ws-device',
              'deviceName': 'Phase 4 WS',
            },
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        await server.libraryManager.scanMusicFolder(musicDir.path);

        await Future.any([
          completer.future,
          Future<void>.delayed(
            const Duration(seconds: 20),
            () => throw StateError(
              'Timed out waiting for library_updated + sync_token_advanced',
            ),
          ),
        ]);

        expect(libraryUpdated, isNotNull);
        expect(syncTokenAdvanced, isNotNull);
        final syncData = syncTokenAdvanced!['data'] as Map<String, dynamic>?;
        expect(syncData, isNotNull);
        expect(syncData!['reason'], equals('scan_complete'));
        expect(syncData['latestToken'], isA<int>());
        expect(syncData['latestToken'] as int, greaterThan(0));

        await subscription.cancel();
        await webSocket.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'PF-5: invalid flag combo enableDownloadJobs=true with enableV2Api=false is rejected',
      () {
        expect(
          () => server.setFeatureFlags(
            const AriamiFeatureFlags(
              enableV2Api: false,
              enableDownloadJobs: true,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('enableDownloadJobs=true requires enableV2Api=true'),
            ),
          ),
        );
      },
    );

    test(
      'PF-5: v2 startup requires catalog repository availability',
      () async {
        // Force catalog initialization failure so repository is unavailable.
        server.libraryManager
            .setCachePath('/dev/null/ariami-invalid/metadata_cache.json');
        server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));

        final port = await _findFreePort();
        await expectLater(
          () => server.start(
            advertisedIp: '127.0.0.1',
            bindAddress: '127.0.0.1',
            port: port,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('requires catalog repository availability'),
            ),
          ),
        );
      },
    );
  });
}

void _seedCatalog(CatalogRepository repository) {
  repository.upsertAlbum(
    CatalogAlbumRecord(
      id: 'album-a',
      title: 'Album A',
      artist: 'Artist A',
      year: 2021,
      coverArtKey: 'album-a',
      songCount: 1,
      durationSeconds: 120,
      updatedToken: 1,
    ),
  );
  repository.upsertAlbum(
    CatalogAlbumRecord(
      id: 'album-b',
      title: 'Album B',
      artist: 'Artist B',
      year: 2022,
      coverArtKey: 'album-b',
      songCount: 1,
      durationSeconds: 180,
      updatedToken: 2,
    ),
  );
  repository.upsertAlbum(
    CatalogAlbumRecord(
      id: 'album-c',
      title: 'Album C',
      artist: 'Artist C',
      year: 2023,
      coverArtKey: 'album-c',
      songCount: 1,
      durationSeconds: 240,
      updatedToken: 3,
    ),
  );

  repository.upsertSong(
    CatalogSongRecord(
      id: 'song-a',
      filePath: '/tmp/song-a.mp3',
      title: 'Song A',
      artist: 'Artist A',
      albumId: 'album-a',
      durationSeconds: 120,
      trackNumber: 1,
      fileSizeBytes: 1000,
      modifiedEpochMs: 100,
      artworkKey: 'album-a',
      updatedToken: 4,
    ),
  );
  repository.upsertSong(
    CatalogSongRecord(
      id: 'song-b',
      filePath: '/tmp/song-b.mp3',
      title: 'Song B',
      artist: 'Artist B',
      albumId: 'album-b',
      durationSeconds: 180,
      trackNumber: 1,
      fileSizeBytes: 1001,
      modifiedEpochMs: 101,
      artworkKey: 'album-b',
      updatedToken: 5,
    ),
  );
  repository.upsertSong(
    CatalogSongRecord(
      id: 'song-c',
      filePath: '/tmp/song-c.mp3',
      title: 'Song C',
      artist: 'Artist C',
      albumId: 'album-c',
      durationSeconds: 240,
      trackNumber: 1,
      fileSizeBytes: 1002,
      modifiedEpochMs: 102,
      artworkKey: 'album-c',
      updatedToken: 6,
    ),
  );

  final now = DateTime.now().millisecondsSinceEpoch;
  repository.appendChangeEvents(<CatalogChangeEventInput>[
    CatalogChangeEventInput(
      entityType: 'album',
      entityId: 'album-a',
      op: 'upsert',
      occurredEpochMs: now,
    ),
    CatalogChangeEventInput(
      entityType: 'song',
      entityId: 'song-a',
      op: 'upsert',
      occurredEpochMs: now + 1,
    ),
    CatalogChangeEventInput(
      entityType: 'song',
      entityId: 'song-b',
      op: 'upsert',
      occurredEpochMs: now + 2,
    ),
    CatalogChangeEventInput(
      entityType: 'song',
      entityId: 'song-c',
      op: 'upsert',
      occurredEpochMs: now + 3,
    ),
  ]);
}

List<String> _extractIds(List<dynamic> rows) {
  return rows
      .map((row) => (row as Map<String, dynamic>)['id'] as String)
      .toList();
}

Future<void> _writeAudioStub(String filePath) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.filled(1024, 0), flush: true);
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _JsonHttpResponse {
  _JsonHttpResponse({
    required this.statusCode,
    required this.jsonBody,
  });

  final int statusCode;
  final Map<String, dynamic> jsonBody;
}

Future<_JsonHttpResponse> _sendJsonRequest({
  required String method,
  required Uri url,
  Map<String, String>? headers,
  Map<String, dynamic>? jsonBody,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    headers?.forEach(request.headers.set);

    if (jsonBody != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(jsonBody));
    }

    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final decoded = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    return _JsonHttpResponse(
      statusCode: response.statusCode,
      jsonBody: decoded,
    );
  } finally {
    client.close(force: true);
  }
}
