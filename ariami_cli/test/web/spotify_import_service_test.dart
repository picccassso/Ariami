import 'dart:convert';
import 'dart:typed_data';

import 'package:ariami_cli/web/services/spotify_import_service.dart';
import 'package:ariami_cli/web/services/web_api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  PlatformFile historyFile(String name, Object json) => PlatformFile(
        name: name,
        size: 1,
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );

  Map<String, dynamic> playRecord() => <String, dynamic>{
        'ts': '2021-03-14T01:23:45Z',
        'platform': 'web_player',
        'ms_played': 45000,
        'master_metadata_track_name': 'The Song',
        'master_metadata_album_artist_name': 'The Artist',
        'master_metadata_album_album_name': 'The Album',
        'spotify_track_uri': 'spotify:track:abc123',
        'reason_end': 'trackdone',
        'offline': false,
        'incognito_mode': false,
      };

  group('decodeSelectedFiles', () {
    test('combines audio files in filename order and ignores other JSON', () {
      final records = SpotifyImportService.decodeSelectedFiles([
        historyFile('other.json', [
          <String, dynamic>{'ignored': true}
        ]),
        historyFile('Streaming_History_Audio_2021.json', [
          <String, dynamic>{'year': 2021},
        ]),
        historyFile('Streaming_History_Audio_2020.json', [
          <String, dynamic>{'year': 2020},
        ]),
      ]);

      expect(records.map((record) => record['year']), [2020, 2021]);
    });

    test('rejects a selection without audio-history files', () {
      expect(
        () => SpotifyImportService.decodeSelectedFiles([
          historyFile('Streaming_History_Video_2021.json', const []),
        ]),
        throwsA(isA<SpotifyImportFailure>()),
      );
    });

    test('rejects malformed JSON', () {
      expect(
        () => SpotifyImportService.decodeSelectedFiles([
          PlatformFile(
            name: 'Streaming_History_Audio_2021.json',
            size: 4,
            bytes: Uint8List.fromList(utf8.encode('{nope')),
          ),
        ]),
        throwsA(
          isA<SpotifyImportFailure>().having(
            (error) => error.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('rejects empty history files', () {
      expect(
        () => SpotifyImportService.decodeSelectedFiles([
          historyFile('Streaming_History_Audio_2021.json', const []),
        ]),
        throwsA(isA<SpotifyImportFailure>()),
      );
    });
  });

  test('analyzes against the full catalog and uploads for the same account',
      () async {
    var meRequests = 0;
    Map<String, dynamic>? uploadBody;
    final client = WebApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/me') {
          meRequests++;
          return http.Response(jsonEncode({'username': 'alex'}), 200);
        }
        if (request.url.path == '/api/v2/bootstrap') {
          expect(request.url.queryParameters['limit'], '500');
          return http.Response(
            jsonEncode({
              'albums': [
                {
                  'id': 'album-1',
                  'title': 'The Album',
                  'artist': 'The Artist',
                  'songCount': 1,
                  'duration': 45,
                }
              ],
              'songs': [
                {
                  'id': 'song-1',
                  'title': 'The Song',
                  'artist': 'The Artist',
                  'albumId': 'album-1',
                  'duration': 45,
                }
              ],
              'playlists': const [],
              'syncToken': 1,
              'pageInfo': {
                'nextCursor': null,
                'hasMore': false,
                'limit': 500,
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/v2/listening/events') {
          uploadBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'accepted': 1, 'duplicates': 0, 'rejected': 0}),
            200,
          );
        }
        return http.Response('not found', 404);
      }),
      tokenProvider: () async => 'token',
      deviceIdProvider: () async => 'cli-web-device',
      deviceName: 'Ariami CLI Web Dashboard',
    );
    final service = SpotifyImportService(client);

    final preview = await service.analyze([playRecord()]);
    expect(preview.accountUsername, 'alex');
    expect(preview.result.events, hasLength(1));
    expect(preview.result.events.single.songId, 'song-1');
    expect(preview.result.events.single.eventId, startsWith('spotify:alex:'));

    final progress = <int>[];
    final result = await service.upload(
      preview,
      onProgress: (sent, _) => progress.add(sent),
    );

    expect(meRequests, 2, reason: 'account is revalidated before upload');
    expect(result.accepted, 1);
    expect(progress, [1]);
    expect(uploadBody?['events'], hasLength(1));
  });
}
