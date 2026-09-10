import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/http_server.dart';
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  test(
      'online ping distinguishes unavailable music and tickets remain retryable',
      () async {
    final temp = await Directory.systemTemp.createTemp('ariami_health_api_');
    final server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    await server.initializeAuth(
      usersFilePath: '${temp.path}/users.json',
      sessionsFilePath: '${temp.path}/sessions.json',
      forceReinitialize: true,
    );
    final port = await startHttpTestServer(server);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
      server.libraryManager.clear();
      await temp.delete(recursive: true);
    });

    Future<({int status, Map<String, dynamic> json, String? retryAfter})> send(
        String path,
        {Map<String, dynamic>? body,
        String? token}) async {
      final request = await client.openUrl(body == null ? 'GET' : 'POST',
          Uri.parse('http://127.0.0.1:$port/api$path'));
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      return (
        status: response.statusCode,
        json: jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>,
        retryAfter: response.headers.value('retry-after'),
      );
    }

    await server.libraryManager.scanMusicFolder('${temp.path}/missing-nas');
    final ping = await send('/ping');
    expect(ping.status, 200);
    expect(ping.json['status'], 'ok');
    expect(ping.json['musicAvailability'], {'status': 'unavailable'});
    expect(jsonEncode(ping.json), isNot(contains(temp.path)),
        reason: 'Public health responses must not expose server paths');

    expect(
        (await send('/auth/register', body: {
          'username': 'owner',
          'password': 'test-password-123',
        }))
            .status,
        200);
    final login = await send('/auth/login', body: {
      'username': 'owner',
      'password': 'test-password-123',
      'deviceId': 'health-test',
      'deviceName': 'Health Test',
    });
    final token = login.json['sessionToken'] as String;
    final ticket = await send('/stream-ticket',
        body: {'songId': 'cached-song'}, token: token);
    expect(ticket.status, 503);
    expect(ticket.json['error']['code'], 'MUSIC_UNAVAILABLE');
    expect(ticket.retryAfter, '30');
    final stats = await send('/stats', token: token);
    expect(stats.json['serverRunning'], isTrue);
    expect(stats.json['musicAvailability'], {'status': 'unavailable'});

    final music = await Directory('${temp.path}/missing-nas').create();
    await File('${music.path}/song.mp3').writeAsBytes(List.filled(4096, 1));
    await server.libraryManager.checkMusicAvailability();
    expect(
        (await send('/ping')).json['musicAvailability'], {'status': 'ready'});
  });
}
