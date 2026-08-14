import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
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
    directory =
        await Directory.systemTemp.createTemp('ariami_http_artist_images_');
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
    port = await startHttpTestServer(server);
    userAToken = await _login(port, 'user-a', 'pass-a-123456', 'device-a');
    userBToken = await _login(port, 'user-b', 'pass-b-123456', 'device-b');
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  // Valid JPEG header bytes (SOI + APP0 marker)
  final validJpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];

  test('list, put, get, and delete custom artist image', () async {
    // 1. Initial list should be empty
    final initialList = await _get(port, '/api/v2/artists/images', userAToken);
    expect(initialList.statusCode, 200);
    expect((initialList.json['images'] as List), isEmpty);

    // 2. Put custom artist image
    final putRes = await _putBytes(
      port,
      '/api/artists/Daft%20Punk/image',
      userAToken,
      validJpegBytes,
      'image/jpeg',
    );
    expect(putRes.statusCode, 200);
    final imageMap = putRes.json['image'] as Map<String, dynamic>;
    expect(imageMap['artistName'], 'Daft Punk');
    expect(imageMap['artistKey'], 'daft punk');
    expect(imageMap['contentType'], 'image/jpeg');
    expect(imageMap['updatedAt'], isA<int>());

    // 3. List should have 1 item
    final listAfterPut =
        await _get(port, '/api/v2/artists/images', userAToken);
    expect(listAfterPut.statusCode, 200);
    final images = listAfterPut.json['images'] as List;
    expect(images, hasLength(1));
    expect(images[0]['artistKey'], 'daft punk');

    // 4. Get raw image bytes
    final getRes =
        await _getBytes(port, '/api/artists/Daft%20Punk/image', userAToken);
    expect(getRes.statusCode, 200);
    expect(getRes.headers.value('content-type'), 'image/jpeg');
    expect(getRes.headers.value('cache-control'), contains('immutable'));
    expect(getRes.bodyBytes, validJpegBytes);

    // 5. Delete custom artist image
    final delRes =
        await _delete(port, '/api/artists/Daft%20Punk/image', userAToken);
    expect(delRes.statusCode, 200);
    expect(delRes.json['removed'], isTrue);

    // 6. Get raw image should now 404
    final getAfterDel =
        await _getBytes(port, '/api/artists/Daft%20Punk/image', userAToken);
    expect(getAfterDel.statusCode, 404);
  });

  test('artist images are isolated per user', () async {
    // User A uploads
    await _putBytes(
      port,
      '/api/artists/Radiohead/image',
      userAToken,
      validJpegBytes,
      'image/jpeg',
    );

    // User B list should still be empty
    final listB = await _get(port, '/api/v2/artists/images', userBToken);
    expect(listB.statusCode, 200);
    expect((listB.json['images'] as List), isEmpty);

    // User B get should 404
    final getB =
        await _getBytes(port, '/api/artists/Radiohead/image', userBToken);
    expect(getB.statusCode, 404);
  });

  test('rejects invalid image payload (magic bytes mismatch)', () async {
    final putRes = await _putBytes(
      port,
      '/api/artists/Invalid/image',
      userAToken,
      <int>[1, 2, 3, 4, 5],
      'image/jpeg',
    );
    expect(putRes.statusCode, 400);
    expect(putRes.json['error']['code'], 'INVALID_ARTIST_IMAGE');
  });
}

Future<String> _login(
    int port, String username, String password, String deviceId) async {
  final client = HttpClient();
  try {
    final req =
        await client.postUrl(Uri.parse('http://127.0.0.1:$port/api/auth/login'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': 'Device $deviceId',
      'clientType': 'desktop',
    }));
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    final map = jsonDecode(body) as Map<String, dynamic>;
    return map['sessionToken'] as String;
  } finally {
    client.close();
  }
}

class _TestResponse {
  _TestResponse(this.statusCode, this.json);
  final int statusCode;
  final Map<String, dynamic> json;
}

class _TestByteResponse {
  _TestByteResponse(this.statusCode, this.headers, this.bodyBytes);
  final int statusCode;
  final HttpHeaders headers;
  final List<int> bodyBytes;
}

Future<_TestResponse> _get(int port, String path, String token) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    return _TestResponse(
      res.statusCode,
      body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>,
    );
  } finally {
    client.close();
  }
}

Future<_TestByteResponse> _getBytes(
    int port, String path, String token) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final bytes = await res.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    return _TestByteResponse(res.statusCode, res.headers, bytes);
  } finally {
    client.close();
  }
}

Future<_TestResponse> _putBytes(
  int port,
  String path,
  String token,
  List<int> bytes,
  String contentType,
) async {
  final client = HttpClient();
  try {
    final req = await client.putUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', contentType);
    req.add(bytes);
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    return _TestResponse(
      res.statusCode,
      body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>,
    );
  } finally {
    client.close();
  }
}

Future<_TestResponse> _delete(int port, String path, String token) async {
  final client = HttpClient();
  try {
    final req =
        await client.deleteUrl(Uri.parse('http://127.0.0.1:$port$path'));
    req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    return _TestResponse(
      res.statusCode,
      body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>,
    );
  } finally {
    client.close();
  }
}
