import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/models/quality_preset.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:ariami_core/services/transcoding/transcoding_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  group('HTTP server web player and M4A streaming', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late Directory playerDir;
    late Directory cliWebDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.setWebAssetsPath(null);
      server.setWebPlayerAssetsPath(null);
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_web_player_');
      playerDir = Directory(p.join(testDir.path, 'web_player'))
        ..createSync(recursive: true);
      File(p.join(playerDir.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><body>ariami web player</body></html>',
      );
      File(p.join(playerDir.path, 'main.dart.js'))
          .writeAsStringSync('// player js');

      cliWebDir = Directory(p.join(testDir.path, 'cli_web'))
        ..createSync(recursive: true);
      File(p.join(cliWebDir.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><body>cli dashboard</body></html>',
      );

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
      server.setWebAssetsPath(null);
      server.setWebPlayerAssetsPath(null);
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('serves /play/, redirects /play and / in desktop mode, keeps /api auth',
        () async {
      server.setFeatureFlags(
        const AriamiFeatureFlags(enableApiScopedAuthForCliWeb: false),
      );
      server.setWebPlayerAssetsPath(playerDir.path);
      final port = await startHttpTestServer(server);

      expect(server.getServerInfo()['webPlayerEnabled'], isTrue);

      final reg = await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        body: {'username': 'owner', 'password': 'password123'},
      );
      expect(reg.statusCode, 200);

      final rootRedirect = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/'),
      );
      expect(rootRedirect.statusCode, 302);
      expect(rootRedirect.location, '/play/');

      final playRedirect = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/play?foo=bar'),
      );
      expect(playRedirect.statusCode, 302);
      expect(playRedirect.location, '/play/?foo=bar');

      final playIndex = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/play/'),
      );
      expect(playIndex.statusCode, 200);
      expect(playIndex.body, contains('ariami web player'));
      expect(playIndex.cacheControl, 'no-cache');

      final playJs = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/play/main.dart.js'),
      );
      expect(playJs.statusCode, 200);
      expect(playJs.body, '// player js');

      final spaRoute = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/play/album/42'),
      );
      expect(spaRoute.statusCode, 200);
      expect(spaRoute.body, contains('ariami web player'));

      final missingAsset = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/play/missing.png'),
      );
      expect(missingAsset.statusCode, 404);

      final apiAlbums = await _sendJson(
        'GET',
        Uri.parse('http://127.0.0.1:$port/api/albums'),
      );
      expect(apiAlbums.statusCode, 401);
    });

    test('coexists with CLI web dashboard and exposes CORS range headers',
        () async {
      server.setFeatureFlags(
        const AriamiFeatureFlags(enableApiScopedAuthForCliWeb: true),
      );
      server.setWebAssetsPath(cliWebDir.path);
      server.setWebPlayerAssetsPath(playerDir.path);
      final port = await startHttpTestServer(server);

      final cliRoot = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/'),
        headers: {'Origin': 'http://localhost:8080'},
      );
      expect(cliRoot.statusCode, 200);
      expect(cliRoot.body, contains('cli dashboard'));
      expect(cliRoot.allowHeaders, contains('Range'));
      expect(
        cliRoot.exposeHeaders,
        'Content-Length, Content-Range, Accept-Ranges',
      );

      final playerIndex = await _sendRaw(
        Uri.parse('http://127.0.0.1:$port/play/'),
      );
      expect(playerIndex.statusCode, 200);
      expect(playerIndex.body, contains('ariami web player'));
    });

    test('registers web clientType in AriamiConnectHub over /api/ws',
        () async {
      final port = await startHttpTestServer(server);
      await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        body: {'username': 'ws-user', 'password': 'ws-password'},
      );
      final login = await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        body: {
          'username': 'ws-user',
          'password': 'ws-password',
          'deviceId': 'web_client_1',
          'deviceName': 'Chrome on macOS',
        },
      );
      final token = login.jsonBody['sessionToken'] as String;

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/api/ws');
      final received = <Map<String, dynamic>>[];
      final welcomeCompleter = Completer<void>();
      final devicesCompleter = Completer<void>();
      final sub = ws.listen((raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        received.add(msg);
        if (msg['type'] == 'connect_welcome' && !welcomeCompleter.isCompleted) {
          welcomeCompleter.complete();
        }
        if (msg['type'] == 'connect_devices' && !devicesCompleter.isCompleted) {
          devicesCompleter.complete();
        }
      });

      try {
        ws.add(jsonEncode(IdentifyMessage(
          deviceId: 'web_client_1',
          deviceName: 'Chrome on macOS',
          sessionToken: token,
          clientType: 'web',
        ).toJson()));

        await Future.wait([welcomeCompleter.future, devicesCompleter.future])
            .timeout(const Duration(seconds: 5));

        final devicesMsg =
            received.firstWhere((m) => m['type'] == 'connect_devices');
        final devices =
            (devicesMsg['data'] as Map<String, dynamic>)['devices'] as List;
        expect(devices.single['type'], 'web');
      } finally {
        await sub.cancel();
        await ws.close();
      }
    });

    test('validates stream ticket/stream format and serves M4A range streams',
        () async {
      final musicDir = Directory(p.join(testDir.path, 'music'))..createSync();
      final sourceFile = File(p.join(musicDir.path, 'Artist - Track.mp3'))
        ..writeAsBytesSync(List<int>.filled(1024, 9));
      await server.libraryManager.scanMusicFolder(musicDir.path);
      final songId = (server.libraryManager.toApiJson('http://127.0.0.1')['songs']
              as List)
          .single['id'] as String;

      final m4aFile = File(p.join(testDir.path, 'cache', 'high', '$songId.m4a'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List<int>.generate(24, (i) => i + 10));

      final fakeTranscoder = _TrackingTranscodingService(
        cacheDirectory: p.join(testDir.path, 'cache'),
        m4aFile: m4aFile,
      );
      server.setTranscodingService(fakeTranscoder);

      final port = await startHttpTestServer(server);
      await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        body: {'username': 'stream-user', 'password': 'stream-password'},
      );
      final login = await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        body: {
          'username': 'stream-user',
          'password': 'stream-password',
          'deviceId': 'web_client_2',
          'deviceName': 'Safari on macOS',
        },
      );
      final sessionToken = login.jsonBody['sessionToken'] as String;
      final authHeaders = {'Authorization': 'Bearer $sessionToken'};

      final badTicket = await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/stream-ticket'),
        headers: authHeaders,
        body: {'songId': songId, 'quality': 'high', 'format': 'opus'},
      );
      expect(badTicket.statusCode, 400);

      final m4aTicket = await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/stream-ticket'),
        headers: authHeaders,
        body: {'songId': songId, 'quality': 'high', 'format': 'm4a'},
      );
      expect(m4aTicket.statusCode, 200);
      final m4aToken = m4aTicket.jsonBody['streamToken'] as String;

      final mismatched = await _sendRaw(
        Uri.parse(
          'http://127.0.0.1:$port/api/stream/$songId?streamToken=$m4aToken&quality=high',
        ),
      );
      expect(m4aToken, isNotEmpty);
      expect(mismatched.statusCode, 403);

      final rangedM4a = await _sendRaw(
        Uri.parse(
          'http://127.0.0.1:$port/api/stream/$songId?streamToken=$m4aToken&quality=high&format=m4a',
        ),
        headers: {'Range': 'bytes=0-7'},
      );
      expect(rangedM4a.statusCode, 206);
      expect(rangedM4a.contentType, 'audio/mp4');
      expect(rangedM4a.bodyBytes, List<int>.generate(8, (i) => i + 10));
      expect(fakeTranscoder.streamingPartialCalls, 0);
      expect(fakeTranscoder.lastFormat, TranscodeOutputFormat.m4a);
      expect(fakeTranscoder.inUseEvents, ['mark:m4a', 'release:m4a']);

      // Legacy stream without format still serves the original high file.
      final legacyTicket = await _sendJson(
        'POST',
        Uri.parse('http://127.0.0.1:$port/api/stream-ticket'),
        headers: authHeaders,
        body: {'songId': songId, 'quality': 'high'},
      );
      expect(legacyTicket.statusCode, 200);
      final legacyToken = legacyTicket.jsonBody['streamToken'] as String;
      final legacyStream = await _sendRaw(
        Uri.parse(
          'http://127.0.0.1:$port/api/stream/$songId?streamToken=$legacyToken&quality=high',
        ),
      );
      expect(legacyStream.statusCode, 200);
      expect(legacyStream.bodyBytes.length, sourceFile.lengthSync());
    });
  });
}

class _TrackingTranscodingService extends TranscodingService {
  _TrackingTranscodingService({
    required super.cacheDirectory,
    required this.m4aFile,
  });

  final File m4aFile;
  int streamingPartialCalls = 0;
  TranscodeOutputFormat? lastFormat;
  final List<String> inUseEvents = [];

  @override
  Future<File?> getTranscodedFile(
    String sourcePath,
    String songId,
    QualityPreset quality, {
    TranscodeRequestType requestType = TranscodeRequestType.streaming,
    TranscodeOutputFormat outputFormat = TranscodeOutputFormat.aac,
    int? sourceBitrateKbps,
  }) async {
    lastFormat = outputFormat;
    return outputFormat == TranscodeOutputFormat.m4a ? m4aFile : null;
  }

  @override
  File streamingPartialFile(
    String songId,
    QualityPreset quality, {
    TranscodeOutputFormat outputFormat = TranscodeOutputFormat.aac,
  }) {
    streamingPartialCalls++;
    return super.streamingPartialFile(songId, quality, outputFormat: outputFormat);
  }

  @override
  void markInUse(
    String songId,
    QualityPreset quality, {
    TranscodeOutputFormat outputFormat = TranscodeOutputFormat.aac,
  }) {
    inUseEvents.add('mark:${outputFormat.name}');
    super.markInUse(songId, quality, outputFormat: outputFormat);
  }

  @override
  void releaseInUse(
    String songId,
    QualityPreset quality, {
    TranscodeOutputFormat outputFormat = TranscodeOutputFormat.aac,
  }) {
    inUseEvents.add('release:${outputFormat.name}');
    super.releaseInUse(songId, quality, outputFormat: outputFormat);
  }
}

class _RawResponse {
  _RawResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final List<int> bodyBytes;
  final HttpHeaders headers;

  String get body => utf8.decode(bodyBytes);
  String? get location => headers.value(HttpHeaders.locationHeader);
  String? get cacheControl => headers.value('cache-control');
  String? get contentType => headers.value(HttpHeaders.contentTypeHeader);
  String? get allowHeaders => headers.value('access-control-allow-headers');
  String? get exposeHeaders => headers.value('access-control-expose-headers');
}

class _JsonResponse {
  _JsonResponse({required this.statusCode, required this.jsonBody});

  final int statusCode;
  final Map<String, dynamic> jsonBody;
}

Future<_RawResponse> _sendRaw(Uri url, {Map<String, String>? headers}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    headers?.forEach(request.headers.set);
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return _RawResponse(
      statusCode: response.statusCode,
      bodyBytes: bytes,
      headers: response.headers,
    );
  } finally {
    client.close(force: true);
  }
}

Future<_JsonResponse> _sendJson(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final request =
        method == 'POST' ? await client.postUrl(url) : await client.getUrl(url);
    headers?.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    return _JsonResponse(
      statusCode: response.statusCode,
      jsonBody: raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}
