import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late AriamiHttpServer server;
  late Directory directory;
  late int port;
  late String userAToken;

  setUp(() async {
    server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    directory =
        await Directory.systemTemp.createTemp('ariami_http_listening_reset_');
    server.libraryManager
        .setCachePath(p.join(directory.path, 'metadata_cache.json'));
    server.setFeatureFlags(const AriamiFeatureFlags(enableV2Api: true));
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    await AuthService().register('user-a', 'pass-a-123456');
    await server.start(
      advertisedIp: '127.0.0.1',
      bindAddress: '127.0.0.1',
      port: 0,
    );
    port = server.getServerInfo()['port'] as int;
    userAToken = await _login(port, 'user-a', 'pass-a-123456', 'device-a');
  });

  tearDown(() async {
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  Future<void> seedMixedHistory() async {
    final cleared = await _request(
      port,
      'POST',
      '/api/v2/listening/reset',
      token: userAToken,
      body: {},
    );
    expect(cleared.statusCode, 200);
    final seeded = await _request(
      port,
      'POST',
      '/api/v2/listening/events',
      token: userAToken,
      body: {
        'events': [
          {
            'eventId': 'spotify:user-a:seed:$port',
            'songId': 'spotify-song',
            'listenedMs': 60000,
            'plays': 1,
            'occurredAtMs': 1700000000000,
          },
          {
            'eventId': 'live:user-a:seed:$port',
            'songId': 'live-song',
            'listenedMs': 30000,
            'plays': 1,
            'occurredAtMs': 1700000060000,
          },
        ],
      },
    );
    expect(seeded.statusCode, 200);
    expect(seeded.json['accepted'], 2);
  }

  test('invalid non-empty reset bodies are rejected without wiping stats',
      () async {
    await seedMixedHistory();

    final invalidBodies = <Map<String, dynamic>>[
      {'source': 'apple'},
      {'source': null},
      {'source': 42},
      {'other': 'value'},
    ];

    for (final body in invalidBodies) {
      final reset = await _request(
        port,
        'POST',
        '/api/v2/listening/reset',
        token: userAToken,
        body: body,
      );
      expect(reset.statusCode, 400, reason: 'body: $body');
      expect((reset.json['error'] as Map)['code'], 'INVALID_REQUEST');

      final summary = await _request(
        port,
        'GET',
        '/api/v2/listening/summary',
        token: userAToken,
      );
      expect(summary.statusCode, 200);
      expect(summary.json['totalListenedMs'], 90000);
      expect(summary.json['totalPlays'], 2);
      // The seeded Spotify event survives every rejected reset.
      expect(summary.json['hasSpotifyImport'], isTrue);
      final songs = {
        for (final song in summary.json['songs'] as List<dynamic>)
          (song as Map)['songId'] as String: song['listenedMs'],
      };
      expect(songs['spotify-song'], 60000);
      expect(songs['live-song'], 30000);
    }
  });

  test('Spotify reset removes only imported events over HTTP', () async {
    await seedMixedHistory();

    final reset = await _request(
      port,
      'POST',
      '/api/v2/listening/reset',
      token: userAToken,
      body: {'source': 'spotify'},
    );
    expect(reset.statusCode, 200);
    expect(reset.json['deleted'], 1);

    final summary = await _request(
      port,
      'GET',
      '/api/v2/listening/summary',
      token: userAToken,
    );
    expect(summary.json['totalListenedMs'], 30000);
    expect(summary.json['totalPlays'], 1);
    expect(summary.json['hasSpotifyImport'], isFalse);
    expect(
      (summary.json['songs'] as List<dynamic>)
          .map((song) => (song as Map)['songId']),
      ['live-song'],
    );
  });

  test('empty-object reset keeps the established full-wipe behavior', () async {
    await seedMixedHistory();

    final reset = await _request(
      port,
      'POST',
      '/api/v2/listening/reset',
      token: userAToken,
      body: {},
    );
    expect(reset.statusCode, 200);
    expect(reset.json.containsKey('deleted'), isFalse);

    final summary = await _request(
      port,
      'GET',
      '/api/v2/listening/summary',
      token: userAToken,
    );
    expect(summary.json['totalListenedMs'], 0);
    expect(summary.json['totalPlays'], 0);
    expect(summary.json['songs'], isEmpty);
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
