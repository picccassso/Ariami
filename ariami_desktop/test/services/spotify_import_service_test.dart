import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
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
}
