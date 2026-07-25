import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:ariami_desktop/models/dashboard_http_response.dart';
import 'package:ariami_desktop/services/dashboard_admin_api_service.dart';
import 'package:ariami_desktop/services/spotify_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readExportFolder', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ariami_spotify_test_');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('reads audio-history files in filename order', () async {
      await File('${directory.path}/Streaming_History_Audio_2021.json')
          .writeAsString(jsonEncode([
        {'year': 2021},
      ]));
      await File('${directory.path}/Streaming_History_Audio_2020.json')
          .writeAsString(jsonEncode([
        {'year': 2020},
      ]));
      await File('${directory.path}/Streaming_History_Video_2020.json')
          .writeAsString(jsonEncode([
        {'ignored': true},
      ]));

      final records =
          await DesktopSpotifyImportService.readExportFolder(directory.path);

      expect(records.map((record) => record['year']), [2020, 2021]);
    });

    test('rejects a folder without audio-history files', () async {
      await expectLater(
        DesktopSpotifyImportService.readExportFolder(directory.path),
        throwsA(isA<DesktopSpotifyImportFailure>()),
      );
    });

    test('rejects malformed JSON', () async {
      await File('${directory.path}/Streaming_History_Audio_2020.json')
          .writeAsString('{nope');

      await expectLater(
        DesktopSpotifyImportService.readExportFolder(directory.path),
        throwsA(
          isA<DesktopSpotifyImportFailure>().having(
            (error) => error.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });
  });

  test('catalogForLibrary preserves Ariami song and album identities', () {
    const albumSong = SongMetadata(
      filePath: '/music/Album/Song.flac',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: 123,
    );
    const standalone = SongMetadata(
      filePath: '/music/Loose.flac',
      title: 'Loose',
      artist: 'Artist',
      duration: 45,
    );
    const library = LibraryStructure(
      albums: {
        'album-1': Album(
          id: 'album-1',
          title: 'Album',
          artist: 'Artist',
          songs: [albumSong],
        ),
      },
      standaloneSongs: [standalone],
    );

    final catalog = DesktopSpotifyImportService.catalogForLibrary(library);

    expect(catalog, hasLength(2));
    expect(catalog.first.songId, defaultGenerateSongId(albumSong.filePath));
    expect(catalog.first.albumId, 'album-1');
    expect(catalog.first.album, 'Album');
    expect(catalog.first.durationMs, 123000);
    expect(catalog.last.songId, defaultGenerateSongId(standalone.filePath));
    expect(catalog.last.albumId, isNull);
  });

  group('removeImportedStats', () {
    DesktopSpotifyImportService serviceWith(_FakeAdminApi adminApi) =>
        DesktopSpotifyImportService(
          httpServer: AriamiHttpServer(),
          adminApi: adminApi,
        );

    test('resets only the Spotify source and returns the deleted count',
        () async {
      final adminApi = _FakeAdminApi(const DashboardHttpResponse(
        statusCode: 200,
        body: '',
        jsonBody: {'success': true, 'deleted': 42},
      ));

      expect(await serviceWith(adminApi).removeImportedStats(), 42);
      expect(adminApi.capturedPath, '/api/v2/listening/reset');
      expect(
        adminApi.capturedBody,
        {'source': 'spotify'},
        reason: 'an empty body would wipe the whole listening history',
      );
    });

    test('surfaces a server failure', () async {
      final adminApi = _FakeAdminApi(const DashboardHttpResponse(
        statusCode: 500,
        body: 'boom',
      ));

      await expectLater(
        serviceWith(adminApi).removeImportedStats(),
        throwsA(isA<DesktopSpotifyImportFailure>()),
      );
    });
  });
}

/// Captures the dashboard request instead of hitting the local server.
class _FakeAdminApi extends DashboardAdminApiService {
  _FakeAdminApi(this._response)
      : super(
          httpServer: AriamiHttpServer(),
          promptCredentials: () async => null,
          showMessage: (_, {bool isError = false}) {},
          isMounted: () => true,
        );

  final DashboardHttpResponse? _response;

  String? capturedPath;
  Map<String, dynamic>? capturedBody;

  @override
  Future<DashboardHttpResponse?> sendAuthenticatedRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    bool includeDashboardDeviceIdentity = true,
  }) async {
    capturedPath = path;
    capturedBody = body;
    return _response;
  }
}
