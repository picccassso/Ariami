import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/models/artwork_batch_codec.dart';
import 'package:ariami_core/models/artwork_size.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/artwork/artwork_service.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  group('Phase 5 - Artwork cache headers and conditional requests', () {
    late AriamiHttpServer server;
    late Directory testDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));

      testDir = await Directory.systemTemp.createTemp('ariami_phase5_');
      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
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
      'P5-3: artwork endpoints return ETag/Last-Modified and honor If-None-Match',
      () async {
        final musicDir =
            await Directory(p.join(testDir.path, 'music')).create();

        final artworkBytes = base64Decode(
          '/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEBAQEBAPEA8PDw8QDw8QDw8PDw8PFREWFhURFRUYHSggGBolGxUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDQ0NDg0NDisZFRkrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrK//AABEIABQAFAMBIgACEQEDEQH/xAAXAAADAQAAAAAAAAAAAAAAAAAAAQID/8QAFhABAQEAAAAAAAAAAAAAAAAAAQAC/8QAFQEBAQAAAAAAAAAAAAAAAAAAAwX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCfAAH/2Q==',
        );

        await _writeTaggedMp3Stub(
          p.join(musicDir.path, 'album_track_1.mp3'),
          title: 'Track One',
          artist: 'Phase5 Artist',
          album: 'Phase5 Album',
          artworkBytes: artworkBytes,
        );
        await _writeTaggedMp3Stub(
          p.join(musicDir.path, 'album_track_2.mp3'),
          title: 'Track Two',
          artist: 'Phase5 Artist',
          album: 'Phase5 Album',
          artworkBytes: artworkBytes,
        );
        await _writeTaggedMp3Stub(
          p.join(musicDir.path, 'standalone_track.mp3'),
          title: 'Standalone Track',
          artist: 'Phase5 Solo Artist',
          album: null,
          artworkBytes: artworkBytes,
        );

        await server.libraryManager.scanMusicFolder(musicDir.path);

        final port = await startHttpTestServer(server);
        final sessionToken = await _registerAndLogin(port);
        final authHeaders = <String, String>{
          'Authorization': 'Bearer $sessionToken',
        };

        final repository = server.libraryManager.createCatalogRepository();
        expect(repository, isNotNull);
        final albumId = repository!.listAlbumsPage(limit: 10).items.first.id;
        final standaloneSongId = repository
            .listSongsPage(limit: 20)
            .items
            .firstWhere(
              (song) => song.albumId == null,
              orElse: () => throw StateError(
                'Expected at least one standalone song',
              ),
            )
            .id;

        final albumArtworkResponse = await _sendBinaryRequest(
          method: 'GET',
          url: Uri.parse(
              'http://127.0.0.1:$port/api/artwork/$albumId?size=full'),
          headers: authHeaders,
        );
        expect(albumArtworkResponse.statusCode, 200);
        final albumEtag = albumArtworkResponse.headers['etag'];
        final albumLastModified = albumArtworkResponse.headers['last-modified'];
        expect(albumEtag, isNotNull);
        expect(albumLastModified, isNotNull);
        expect(() => HttpDate.parse(albumLastModified!), returnsNormally);

        final albumNotModifiedResponse = await _sendBinaryRequest(
          method: 'GET',
          url: Uri.parse(
              'http://127.0.0.1:$port/api/artwork/$albumId?size=full'),
          headers: <String, String>{
            ...authHeaders,
            'If-None-Match': albumEtag!,
          },
        );
        expect(albumNotModifiedResponse.statusCode, 304);
        expect(albumNotModifiedResponse.headers['etag'], equals(albumEtag));

        final songArtworkResponse = await _sendBinaryRequest(
          method: 'GET',
          url: Uri.parse(
            'http://127.0.0.1:$port/api/song-artwork/$standaloneSongId?size=full',
          ),
          headers: authHeaders,
        );
        expect(songArtworkResponse.statusCode, 200);
        final songEtag = songArtworkResponse.headers['etag'];
        final songLastModified = songArtworkResponse.headers['last-modified'];
        expect(songEtag, isNotNull);
        expect(songLastModified, isNotNull);
        expect(() => HttpDate.parse(songLastModified!), returnsNormally);

        final songNotModifiedResponse = await _sendBinaryRequest(
          method: 'GET',
          url: Uri.parse(
            'http://127.0.0.1:$port/api/song-artwork/$standaloneSongId?size=full',
          ),
          headers: <String, String>{
            ...authHeaders,
            'If-None-Match': songEtag!,
          },
        );
        expect(songNotModifiedResponse.statusCode, 304);
        expect(songNotModifiedResponse.headers['etag'], equals(songEtag));
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test(
      'fast-path WebP negotiation and POST /api/artwork/batch return framed results',
      () async {
        final musicDir =
            await Directory(p.join(testDir.path, 'music_batch')).create();
        final artworkBytes = base64Decode(
          '/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEBAQEBAPEA8PDw8QDw8QDw8PDw8PFREWFhURFRUYHSggGBolGxUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDQ0NDg0NDisZFRkrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrKysrK//AABEIABQAFAMBIgACEQEDEQH/xAAXAAADAQAAAAAAAAAAAAAAAAAAAQID/8QAFhABAQEAAAAAAAAAAAAAAAAAAQAC/8QAFQEBAQAAAAAAAAAAAAAAAAAAAwX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCfAAH/2Q==',
        );
        await _writeTaggedMp3Stub(
          p.join(musicDir.path, 'a1.mp3'),
          title: 'A1',
          artist: 'Artist',
          album: 'Album',
          artworkBytes: artworkBytes,
        );
        await _writeTaggedMp3Stub(
          p.join(musicDir.path, 'a2.mp3'),
          title: 'A2',
          artist: 'Artist',
          album: 'Album',
          artworkBytes: artworkBytes,
        );
        await _writeTaggedMp3Stub(
          p.join(musicDir.path, 'solo.mp3'),
          title: 'Solo',
          artist: 'Solo Artist',
          album: null,
          artworkBytes: artworkBytes,
        );

        Future<ProcessResult> fakeWebpFfmpeg(
          String executable,
          List<String> args,
        ) async {
          if (args.contains('-version')) {
            return ProcessResult(1, 0, 'ffmpeg stub', '');
          }
          if (args.contains('-encoders')) {
            return ProcessResult(1, 0, ' V....D libwebp WebP image', '');
          }
          final outPath = args.last;
          await File(outPath).writeAsBytes(const <int>[0x52, 0x49, 0x46, 0x46]);
          return ProcessResult(2, 0, '', '');
        }

        server.setArtworkService(ArtworkService(
          cacheDirectory: p.join(testDir.path, 'art_cache'),
          processRunner: fakeWebpFfmpeg,
        ));

        await server.libraryManager.scanMusicFolder(musicDir.path);
        final port = await startHttpTestServer(server);
        final sessionToken = await _registerAndLogin(port);
        final authHeaders = <String, String>{
          'Authorization': 'Bearer $sessionToken',
          'Accept': 'image/webp,image/jpeg,*/*',
        };

        final repository = server.libraryManager.createCatalogRepository()!;
        final albumId = repository.listAlbumsPage(limit: 10).items.first.id;
        final standaloneId = repository
            .listSongsPage(limit: 20)
            .items
            .firstWhere((s) => s.albumId == null)
            .id;

        final webpRes = await _sendBinaryRequest(
          method: 'GET',
          url: Uri.parse(
            'http://127.0.0.1:$port/api/artwork/$albumId?size=thumbnail',
          ),
          headers: authHeaders,
        );
        expect(webpRes.statusCode, 200);
        expect(webpRes.headers['content-type'], 'image/webp');
        expect(webpRes.headers['cache-control'], contains('immutable'));

        // Unauthenticated batch must be rejected.
        final unauthClient = HttpClient();
        try {
          final req = await unauthClient.postUrl(
            Uri.parse('http://127.0.0.1:$port/api/artwork/batch'),
          );
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode({'albums': [albumId]}));
          final res = await req.close();
          expect(res.statusCode, 401);
          await res.drain<void>();
        } finally {
          unauthClient.close(force: true);
        }

        // Authenticated batch returns album, standalone song, and missing item.
        final batchClient = HttpClient();
        try {
          final req = await batchClient.postUrl(
            Uri.parse('http://127.0.0.1:$port/api/artwork/batch'),
          );
          req.headers.contentType = ContentType.json;
          req.headers.set('Authorization', 'Bearer $sessionToken');
          req.write(jsonEncode({
            'size': ArtworkSize.thumbnail.name,
            'format': 'webp',
            'albums': [albumId, 'nonexistent-album'],
            'songs': [standaloneId],
          }));
          final res = await req.close();
          expect(res.statusCode, 200);
          final builder = BytesBuilder(copy: false);
          await for (final chunk in res) {
            builder.add(chunk);
          }
          final decoded = ArtworkBatchCodec.decode(builder.takeBytes());
          final byKey = {for (final item in decoded) item.key: item};
          expect(byKey[ArtworkBatchCodec.albumKey(albumId)]?.found, isTrue);
          expect(
            byKey[ArtworkBatchCodec.albumKey(albumId)]?.contentType,
            'image/webp',
          );
          expect(byKey[ArtworkBatchCodec.songKey(standaloneId)]?.found, isTrue);
          expect(
            byKey[ArtworkBatchCodec.albumKey('nonexistent-album')]?.found,
            isFalse,
          );
        } finally {
          batchClient.close(force: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  });
}

class _BinaryHttpResponse {
  _BinaryHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}

Future<_BinaryHttpResponse> _sendBinaryRequest({
  required String method,
  required Uri url,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    headers?.forEach(request.headers.set);
    final response = await request.close();

    final normalizedHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      normalizedHeaders[name.toLowerCase()] = values.join(', ');
    });

    final bytesBuilder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytesBuilder.add(chunk);
    }

    return _BinaryHttpResponse(
      statusCode: response.statusCode,
      headers: normalizedHeaders,
      body: bytesBuilder.takeBytes(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<String> _registerAndLogin(int port) async {
  final client = HttpClient();
  try {
    await _postJson(
      client,
      Uri.parse('http://127.0.0.1:$port/api/auth/register'),
      <String, dynamic>{
        'username': 'artwork-owner',
        'password': 'artwork-pass',
      },
    );
    final login = await _postJson(
      client,
      Uri.parse('http://127.0.0.1:$port/api/auth/login'),
      <String, dynamic>{
        'username': 'artwork-owner',
        'password': 'artwork-pass',
        'deviceId': 'artwork-device',
        'deviceName': 'Artwork Device',
      },
    );
    return login['sessionToken'] as String;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _postJson(
  HttpClient client,
  Uri uri,
  Map<String, dynamic> payload,
) async {
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(payload));

  final response = await request.close();
  expect(response.statusCode, inInclusiveRange(200, 299));
  final body = await response.transform(utf8.decoder).join();
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<void> _writeTaggedMp3Stub(
  String filePath, {
  required String title,
  required String artist,
  required String? album,
  required List<int> artworkBytes,
}) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);

  final tagBytes = _buildId3v24Tag(
    title: title,
    artist: artist,
    album: album,
    artworkBytes: artworkBytes,
  );

  final payload = BytesBuilder(copy: false)
    ..add(tagBytes)
    ..add(List<int>.filled(256, 0));
  await file.writeAsBytes(payload.takeBytes(), flush: true);
}

Uint8List _buildId3v24Tag({
  required String title,
  required String artist,
  required String? album,
  required List<int> artworkBytes,
}) {
  final frames = BytesBuilder(copy: false)
    ..add(_buildTextFrame('TIT2', title))
    ..add(_buildTextFrame('TPE1', artist));

  if (album != null && album.isNotEmpty) {
    frames
      ..add(_buildTextFrame('TALB', album))
      ..add(_buildTextFrame('TPE2', artist));
  }

  frames.add(_buildApicFrame(artworkBytes));

  final bodyBytes = frames.takeBytes();
  final syncSafeSize = _toSyncSafe(bodyBytes.length);

  final tag = BytesBuilder(copy: false)
    ..add(ascii.encode('ID3'))
    ..add(const <int>[0x04, 0x00, 0x00]) // ID3v2.4.0, no flags
    ..add(syncSafeSize)
    ..add(bodyBytes);
  return Uint8List.fromList(tag.takeBytes());
}

Uint8List _buildTextFrame(String frameId, String value) {
  final payload = BytesBuilder(copy: false)
    ..addByte(0x00) // ISO-8859-1 encoding
    ..add(latin1.encode(value));
  return _buildFrame(frameId, payload.takeBytes());
}

Uint8List _buildApicFrame(List<int> artworkBytes) {
  final payload = BytesBuilder(copy: false)
    ..addByte(0x00) // ISO-8859-1 encoding
    ..add(ascii.encode('image/jpeg'))
    ..addByte(0x00)
    ..addByte(0x03) // Cover (front)
    ..addByte(0x00) // Empty description
    ..add(artworkBytes);
  return _buildFrame('APIC', payload.takeBytes());
}

Uint8List _buildFrame(String frameId, List<int> payload) {
  final syncSafeSize = _toSyncSafe(payload.length);
  final frame = BytesBuilder(copy: false)
    ..add(ascii.encode(frameId))
    ..add(syncSafeSize)
    ..add(const <int>[0x00, 0x00]) // Frame flags
    ..add(payload);
  return Uint8List.fromList(frame.takeBytes());
}

List<int> _toSyncSafe(int value) {
  return <int>[
    (value >> 21) & 0x7F,
    (value >> 14) & 0x7F,
    (value >> 7) & 0x7F,
    value & 0x7F,
  ];
}
