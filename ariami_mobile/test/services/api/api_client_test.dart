import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiClient.getLibrary', () {
    test('throws when v1 snapshot endpoint is disabled', () async {
      final client = ApiClient(
        serverInfo: ServerInfo(
          server: '127.0.0.1',
          port: 8080,
          name: 'test',
          version: 'test',
        ),
        enableV1LibrarySnapshot: false,
      );

      await expectLater(
        client.getLibrary(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCodes.invalidRequest),
        ),
      );
    });
  });

  group('ApiClient v2 download jobs', () {
    late HttpServer server;
    late ApiClient client;
    late List<_CapturedRequest> capturedRequests;

    setUp(() async {
      capturedRequests = <_CapturedRequest>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _startMockApiServer(server, capturedRequests);

      client = ApiClient(
        serverInfo: ServerInfo(
          server: '127.0.0.1',
          port: server.port,
          name: 'test',
          version: 'test',
        ),
        sessionToken: 'test-session',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('supports create/status/items/cancel download job endpoints',
        () async {
      final create = await client.createV2DownloadJob(
        const DownloadJobCreateRequest(
          songIds: <String>['song-a'],
          albumIds: <String>['album-b'],
          quality: 'medium',
          downloadOriginal: false,
        ),
      );
      expect(create.jobId, equals('dj_123'));
      expect(create.status, equals('ready'));
      expect(create.itemCount, equals(2));

      final status = await client.getV2DownloadJobStatus('dj_123');
      expect(status.status, equals('ready'));
      expect(status.pendingCount, equals(2));
      expect(status.cancelledCount, equals(0));

      final items = await client.getV2DownloadJobItems(
        'dj_123',
        cursor: '5',
        limit: 25,
      );
      expect(items.jobId, equals('dj_123'));
      expect(items.items.length, equals(1));
      expect(items.items.first.songId, equals('song-a'));
      expect(items.pageInfo.cursor, equals('5'));
      expect(items.pageInfo.limit, equals(25));

      final cancel = await client.cancelV2DownloadJob('dj_123');
      expect(cancel.jobId, equals('dj_123'));
      expect(cancel.status, equals('cancelled'));

      expect(capturedRequests.length, equals(4));

      final createRequest = capturedRequests[0];
      expect(createRequest.method, equals('POST'));
      expect(createRequest.path, equals('/api/v2/download-jobs'));
      expect(createRequest.authorizationHeader, equals('Bearer test-session'));
      expect(createRequest.body['songIds'], equals(<dynamic>['song-a']));
      expect(createRequest.body['albumIds'], equals(<dynamic>['album-b']));
      expect(createRequest.body['quality'], equals('medium'));
      expect(createRequest.body['downloadOriginal'], isFalse);

      final statusRequest = capturedRequests[1];
      expect(statusRequest.method, equals('GET'));
      expect(statusRequest.path, equals('/api/v2/download-jobs/dj_123'));

      final itemsRequest = capturedRequests[2];
      expect(itemsRequest.method, equals('GET'));
      expect(itemsRequest.path, equals('/api/v2/download-jobs/dj_123/items'));
      expect(itemsRequest.queryParameters['cursor'], equals('5'));
      expect(itemsRequest.queryParameters['limit'], equals('25'));

      final cancelRequest = capturedRequests[3];
      expect(cancelRequest.method, equals('POST'));
      expect(cancelRequest.path, equals('/api/v2/download-jobs/dj_123/cancel'));
    });
  });
}

void _startMockApiServer(
  HttpServer server,
  List<_CapturedRequest> capturedRequests,
) {
  unawaited(
    server.forEach((request) async {
      final bodyText = await utf8.decoder.bind(request).join();
      final decodedBody = bodyText.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(bodyText) as Map<String, dynamic>;

      capturedRequests.add(
        _CapturedRequest(
          method: request.method,
          path: request.uri.path,
          queryParameters: request.uri.queryParameters,
          authorizationHeader:
              request.headers.value(HttpHeaders.authorizationHeader),
          body: decodedBody,
        ),
      );

      final path = request.uri.path;
      final method = request.method;

      if (path == '/api/v2/download-jobs' && method == 'POST') {
        await _writeJson(
          request.response,
          <String, dynamic>{
            'jobId': 'dj_123',
            'status': 'ready',
            'quality': 'medium',
            'downloadOriginal': false,
            'itemCount': 2,
            'createdAt': '2026-02-07T00:00:00Z',
            'updatedAt': '2026-02-07T00:00:00Z',
          },
        );
        return;
      }

      if (path == '/api/v2/download-jobs/dj_123' && method == 'GET') {
        await _writeJson(
          request.response,
          <String, dynamic>{
            'jobId': 'dj_123',
            'userId': 'user-1',
            'status': 'ready',
            'quality': 'medium',
            'downloadOriginal': false,
            'itemCount': 2,
            'pendingCount': 2,
            'cancelledCount': 0,
            'createdAt': '2026-02-07T00:00:00Z',
            'updatedAt': '2026-02-07T00:00:00Z',
          },
        );
        return;
      }

      if (path == '/api/v2/download-jobs/dj_123/items' && method == 'GET') {
        await _writeJson(
          request.response,
          <String, dynamic>{
            'jobId': 'dj_123',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'itemOrder': 6,
                'songId': 'song-a',
                'status': 'pending',
                'title': 'Song A',
                'artist': 'Artist A',
                'albumId': 'album-a',
                'albumName': 'Album A',
                'albumArtist': 'Artist A',
                'trackNumber': 1,
                'durationSeconds': 120,
                'fileSizeBytes': 1000,
              },
            ],
            'pageInfo': <String, dynamic>{
              'cursor': request.uri.queryParameters['cursor'],
              'nextCursor': null,
              'hasMore': false,
              'limit': int.tryParse(
                    request.uri.queryParameters['limit'] ?? '',
                  ) ??
                  0,
            },
          },
        );
        return;
      }

      if (path == '/api/v2/download-jobs/dj_123/cancel' && method == 'POST') {
        await _writeJson(
          request.response,
          <String, dynamic>{
            'jobId': 'dj_123',
            'status': 'cancelled',
            'cancelledAt': '2026-02-07T00:00:05Z',
          },
        );
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await _writeJson(
        request.response,
        <String, dynamic>{
          'error': <String, dynamic>{
            'code': 'NOT_FOUND',
            'message': 'Route not found in test server',
          },
        },
      );
    }),
  );
}

Future<void> _writeJson(
    HttpResponse response, Map<String, dynamic> body) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.authorizationHeader,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> queryParameters;
  final String? authorizationHeader;
  final Map<String, dynamic> body;
}
