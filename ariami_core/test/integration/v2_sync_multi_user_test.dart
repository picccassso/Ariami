import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Phase 11 - v2 sync multi-user fairness', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_phase11_');
      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      server.setFeatureFlags(
        const AriamiFeatureFlags(enableV2Api: true, enableDownloadJobs: true),
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test(
      'P11-2: concurrent multi-user download-job creation keeps per-user quotas isolated',
      () async {
        await server.initializeAuth(
          usersFilePath: p.join(testDir.path, 'users.json'),
          sessionsFilePath: p.join(testDir.path, 'sessions.json'),
          forceReinitialize: true,
        );

        final repository = server.libraryManager.createCatalogRepository();
        expect(repository, isNotNull);
        _seedCatalog(repository!, songCount: 32);

        final port = await _findFreePort();
        await server.start(
          advertisedIp: '127.0.0.1',
          bindAddress: '127.0.0.1',
          port: port,
        );

        await _registerUser(port, 'user-a', 'pass-a');
        await _registerUser(port, 'user-b', 'pass-b');

        final userAToken = await _loginUser(
          port: port,
          username: 'user-a',
          password: 'pass-a',
          deviceId: 'phase11-device-a',
          deviceName: 'Phase11 Device A',
        );
        final userBToken = await _loginUser(
          port: port,
          username: 'user-b',
          password: 'pass-b',
          deviceId: 'phase11-device-b',
          deviceName: 'Phase11 Device B',
        );

        final userARequests = List.generate(
          10,
          (index) => _createDownloadJob(
            port: port,
            sessionToken: userAToken,
            songId: _songId(index + 1),
          ),
        );
        final userBRequests = List.generate(
          10,
          (index) => _createDownloadJob(
            port: port,
            sessionToken: userBToken,
            songId: _songId(index + 11),
          ),
        );

        final responses = await Future.wait(
          <Future<_JsonResponse>>[
            ...userARequests,
            ...userBRequests,
          ],
        );

        int successA = 0;
        int quotaA = 0;
        int successB = 0;
        int quotaB = 0;

        for (var i = 0; i < responses.length; i++) {
          final response = responses[i];
          final forUserA = i < userARequests.length;

          if (response.statusCode == 200) {
            if (forUserA) {
              successA += 1;
            } else {
              successB += 1;
            }
            continue;
          }

          expect(response.statusCode, equals(429));
          expect(
            (response.jsonBody['error'] as Map<String, dynamic>)['code'],
            equals('QUOTA_EXCEEDED'),
          );
          expect(response.headers['retry-after'], isNotNull);

          if (forUserA) {
            quotaA += 1;
          } else {
            quotaB += 1;
          }
        }

        // Default per-user active job quota is 8.
        expect(successA, equals(8));
        expect(quotaA, equals(2));
        expect(successB, equals(8));
        expect(quotaB, equals(2));
      },
    );
  });
}

void _seedCatalog(CatalogRepository repository, {required int songCount}) {
  repository.upsertAlbum(
    CatalogAlbumRecord(
      id: 'album-main',
      title: 'Main Album',
      artist: 'Load Artist',
      year: 2026,
      coverArtKey: null,
      songCount: songCount,
      durationSeconds: songCount * 180,
      updatedToken: 1,
    ),
  );

  for (var i = 1; i <= songCount; i++) {
    repository.upsertSong(
      CatalogSongRecord(
        id: _songId(i),
        filePath: '/tmp/${_songId(i)}.mp3',
        title: 'Song $i',
        artist: 'Load Artist',
        albumId: 'album-main',
        durationSeconds: 180,
        trackNumber: i,
        fileSizeBytes: 4096 + i,
        modifiedEpochMs: 1700000000000 + i,
        artworkKey: null,
        updatedToken: 1 + i,
      ),
    );
  }
}

String _songId(int index) => 'song-${index.toString().padLeft(4, '0')}';

Future<void> _registerUser(int port, String username, String password) async {
  final response = await _sendJsonRequest(
    method: 'POST',
    url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
    jsonBody: <String, dynamic>{
      'username': username,
      'password': password,
    },
  );
  expect(response.statusCode, equals(200));
}

Future<String> _loginUser({
  required int port,
  required String username,
  required String password,
  required String deviceId,
  required String deviceName,
}) async {
  final response = await _sendJsonRequest(
    method: 'POST',
    url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
    jsonBody: <String, dynamic>{
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
    },
  );
  expect(response.statusCode, equals(200));
  return response.jsonBody['sessionToken'] as String;
}

Future<_JsonResponse> _createDownloadJob({
  required int port,
  required String sessionToken,
  required String songId,
}) {
  return _sendJsonRequest(
    method: 'POST',
    url: Uri.parse('http://127.0.0.1:$port/api/v2/download-jobs'),
    headers: <String, String>{'Authorization': 'Bearer $sessionToken'},
    jsonBody: <String, dynamic>{
      'songIds': <String>[songId],
      'quality': 'high',
      'downloadOriginal': false,
    },
  );
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_JsonResponse> _sendJsonRequest({
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
    final responseBody = await response.transform(utf8.decoder).join();
    final decodedBody = responseBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(responseBody) as Map<String, dynamic>;

    return _JsonResponse(
      statusCode: response.statusCode,
      jsonBody: decodedBody,
      headers: response.headers,
    );
  } finally {
    client.close(force: true);
  }
}

class _JsonResponse {
  _JsonResponse({
    required this.statusCode,
    required this.jsonBody,
    required this.headers,
  });

  final int statusCode;
  final Map<String, dynamic> jsonBody;
  final HttpHeaders headers;
}
