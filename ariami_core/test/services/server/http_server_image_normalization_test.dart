import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ariami_core/services/artwork/image_normalizer.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

/// Uploads are shrunk with the real FFmpeg, so these skip where it is absent.
final bool _hasFfmpeg = () {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}();

void main() {
  late AriamiHttpServer server;
  late Directory directory;
  late int port;
  late String token;

  Future<Uint8List> generate(String name, int width, int height) async {
    final file = File(p.join(directory.path, name));
    final result = await Process.run('ffmpeg', [
      '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'testsrc2=size=${width}x$height:rate=1',
      '-frames:v', '1', '-q:v', '2', file.path, //
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return file.readAsBytes();
  }

  Future<(int, Uint8List)> send(String method, String path,
      {List<int>? body, String? contentType}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
          method, Uri.parse('http://127.0.0.1:$port$path'));
      request.headers.set('Authorization', 'Bearer $token');
      if (contentType != null) request.headers.set('Content-Type', contentType);
      if (body != null) request.add(body);
      final response = await request.close();
      final bytes = await response.fold<BytesBuilder>(
          BytesBuilder(copy: false), (b, chunk) => b..add(chunk));
      return (response.statusCode, bytes.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  (int, int)? dimensions(List<int> bytes) =>
      ImageNormalizer.imageDimensions(bytes, 'image/jpeg');

  Future<void> initializeAuth({bool force = false}) => server.initializeAuth(
        usersFilePath: p.join(directory.path, 'users.json'),
        sessionsFilePath: p.join(directory.path, 'sessions.json'),
        forceReinitialize: force,
      );

  setUp(() async {
    server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    directory = await Directory.systemTemp.createTemp('ariami_normalize_');
    await initializeAuth(force: true);
    await AuthService().register('owner', 'owner-pass-123');
    port = await startHttpTestServer(server);

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port/api/auth/login'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'username': 'owner',
        'password': 'owner-pass-123',
        'deviceId': 'device-1',
        'deviceName': 'Device 1',
        'clientType': 'desktop',
      }));
      final response = await request.close();
      token = (jsonDecode(await utf8.decodeStream(response))
          as Map<String, dynamic>)['sessionToken'] as String;
    } finally {
      client.close();
    }
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  test('oversized uploads are shrunk per image kind', () async {
    final big = await generate('big.jpg', 1600, 1200);

    expect(
        (await send('PUT', '/api/me/avatar',
                body: big, contentType: 'image/jpeg'))
            .$1,
        200);
    expect(dimensions((await send('GET', '/api/me/avatar')).$2), (512, 384));

    expect(
        (await send('PUT', '/api/playlists/p1/image',
                body: big, contentType: 'image/jpeg'))
            .$1,
        200);
    expect(dimensions((await send('GET', '/api/playlists/p1/image')).$2),
        (1200, 900));

    expect(
        (await send('PUT', '/api/artists/Daft%20Punk/image',
                body: big, contentType: 'image/jpeg'))
            .$1,
        200);
    expect(dimensions((await send('GET', '/api/artists/Daft%20Punk/image')).$2),
        (1200, 900));
  }, skip: !_hasFfmpeg);

  test('images within bounds are stored untouched', () async {
    final small = await generate('small.jpg', 400, 300);

    await send('PUT', '/api/me/avatar', body: small, contentType: 'image/jpeg');
    expect((await send('GET', '/api/me/avatar')).$2, small);
  }, skip: !_hasFfmpeg);

  test('startup shrinks an oversized stored avatar and bumps its version',
      () async {
    final big = await generate('big.jpg', 1600, 1200);
    await send('PUT', '/api/me/avatar',
        body: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        contentType: 'image/jpeg');
    final me = jsonDecode(utf8.decode((await send('GET', '/api/me')).$2))
        as Map<String, dynamic>;
    final avatar =
        File(p.join(directory.path, 'user_avatars', '${me['userId']}.jpg'));
    await avatar.writeAsBytes(big);
    final stale = DateTime.now().subtract(const Duration(minutes: 10));
    await avatar.setLastModified(stale);

    await initializeAuth(); // re-runs the background normalisation

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (avatar.lengthSync() == big.length &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(dimensions(await avatar.readAsBytes()), (512, 384));
    expect(avatar.lastModifiedSync().isAfter(stale), isTrue);
  }, skip: !_hasFfmpeg);
}
