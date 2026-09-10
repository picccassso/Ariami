import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ariami_core/models/music_availability.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('music outage stays connected, recovers, and supports older servers',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic> response = {
      'status': 'ok',
      'musicAvailability': {'status': 'unavailable'}
    };
    unawaited(server.forEach((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    }));
    final client = ApiClient(
        serverInfo: ServerInfo(
            server: '127.0.0.1',
            port: server.port,
            name: 'Test',
            version: 'test'));
    final reported = <MusicAvailability>[];
    client.onMusicAvailabilityChanged = reported.add;
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    expect((await client.ping())['status'], 'ok');
    expect(client.musicAvailability, MusicAvailability.unavailable);
    response = {
      'status': 'ok',
      'musicAvailability': {'status': 'ready'}
    };
    expect((await client.ping())['status'], 'ok');
    expect(client.musicAvailability, MusicAvailability.ready);
    response = {'status': 'ok'};
    expect((await client.ping())['status'], 'ok');
    expect(client.musicAvailability, MusicAvailability.unknown);
    expect(reported, [
      MusicAvailability.unavailable,
      MusicAvailability.ready,
      MusicAvailability.unknown
    ]);
  });
}
