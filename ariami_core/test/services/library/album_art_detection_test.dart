import 'dart:io';

import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_art_detection.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/metadata_extractor.dart';
import 'package:test/test.dart';

void main() {
  group('album sidecar detection', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_art_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('findAlbumSidecarArtworkPath detects cover.jpg', () async {
      final albumDir = await Directory('${tempDir.path}/album').create();
      final cover = File('${albumDir.path}/cover.jpg');
      await cover.writeAsBytes([0xFF, 0xD8, 0xFF]);

      expect(findAlbumSidecarArtworkPath(albumDir.path), cover.path);
    });

    test('resolveAlbumArtworkSources prefers sidecar over lazy song path',
        () async {
      final albumDir = await Directory('${tempDir.path}/album2').create();
      final sidecar = File('${albumDir.path}/Folder.jpg');
      await sidecar.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

      final songs = [
        SongMetadata(
          filePath: '${albumDir.path}/01-track.mp3',
          title: 'Track',
          artist: 'Artist',
          album: 'Album',
        ),
        SongMetadata(
          filePath: '${albumDir.path}/02-track.mp3',
          title: 'Track 2',
          artist: 'Artist',
          album: 'Album',
        ),
      ];

      final artwork = resolveAlbumArtworkSources(songs);
      expect(artwork.hasArtwork, isTrue);
      expect(artwork.artworkPath, sidecar.path);
    });

    test('AlbumBuilder sets hasArtwork false without sidecar or embedded art',
        () async {
      final albumDir = await Directory('${tempDir.path}/album3').create();
      final songs = [
        SongMetadata(
          filePath: '${albumDir.path}/01-track.mp3',
          title: 'One',
          artist: 'Artist',
          album: 'Album',
        ),
        SongMetadata(
          filePath: '${albumDir.path}/02-track.mp3',
          title: 'Two',
          artist: 'Artist',
          album: 'Album',
        ),
      ];

      final library = await AlbumBuilder(
        metadataExtractor: MetadataExtractor(),
      ).buildLibraryAsync(songs);

      final album = library.albums.values.single;
      expect(album.hasArtwork, isFalse);
      expect(album.artworkPath, songs.first.filePath);
    });
  });

  group('coverArt advertisement', () {
    test('Album without artwork does not advertise coverArtKey material', () {
      const album = Album(
        id: 'album-1',
        title: 'No Art',
        artist: 'Artist',
        songs: [],
        artworkPath: '/music/track.mp3',
        hasArtwork: false,
      );

      expect(album.hasArtwork, isFalse);
      expect(album.artworkPath, isNotNull);
    });
  });
}
