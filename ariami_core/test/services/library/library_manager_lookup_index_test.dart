import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/library/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('LibraryManager song lookup index', () {
    late LibraryManager manager;

    setUp(() {
      manager = LibraryManager();
      manager.clear();
    });

    tearDown(() {
      manager.clear();
    });

    test('resolves song lookup helpers in a large synthetic library', () {
      const albumCount = 100;
      const songsPerAlbum = 100;
      const standaloneCount = 500;
      final library = _largeLibrary(
        albumCount: albumCount,
        songsPerAlbum: songsPerAlbum,
        standaloneCount: standaloneCount,
      );

      manager.setLibraryForTesting(library);

      final firstAlbumSongPath = '/music/album_000/track_000.mp3';
      final lastAlbumSongPath = '/music/album_099/track_099.mp3';
      final standaloneSongPath = '/music/standalone/track_499.mp3';

      final firstAlbumSongId = _songId(firstAlbumSongPath);
      final lastAlbumSongId = _songId(lastAlbumSongPath);
      final standaloneSongId = _songId(standaloneSongPath);

      expect(manager.getSongFilePath(firstAlbumSongId), firstAlbumSongPath);
      expect(manager.getSongAlbumId(firstAlbumSongId), 'album_000');
      expect(manager.getKnownSongDuration(firstAlbumSongId), 180);
      expect(manager.getKnownSongBitrate(firstAlbumSongId), 96);

      expect(manager.getSongFilePath(lastAlbumSongId), lastAlbumSongPath);
      expect(manager.getSongAlbumId(lastAlbumSongId), 'album_099');
      expect(manager.getKnownSongDuration(lastAlbumSongId), 279);
      expect(manager.getKnownSongBitrate(lastAlbumSongId), 192);

      expect(manager.getSongFilePath(standaloneSongId), standaloneSongPath);
      expect(manager.getSongAlbumId(standaloneSongId), isNull);
      expect(manager.getKnownSongDuration(standaloneSongId), 219);
      expect(manager.getKnownSongBitrate(standaloneSongId), 128);
    });

    test('repeated lookups stay fast for large libraries', () {
      final library = _largeLibrary(
        albumCount: 200,
        songsPerAlbum: 100,
        standaloneCount: 1000,
      );
      manager.setLibraryForTesting(library);

      final lookupIds = <String>[
        _songId('/music/album_000/track_000.mp3'),
        _songId('/music/album_050/track_050.mp3'),
        _songId('/music/album_199/track_099.mp3'),
        _songId('/music/standalone/track_999.mp3'),
      ];

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        final songId = lookupIds[i % lookupIds.length];
        expect(manager.getSongFilePath(songId), isNotNull);
        manager.getSongAlbumId(songId);
        manager.getKnownSongDuration(songId);
      }
      stopwatch.stop();

      // This threshold is intentionally loose for CI, but it catches a return
      // to full-library scans on every lookup.
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('falls back to catalog song rows before library is loaded', () async {
      final tempDir = await Directory.systemTemp.createTemp('ariami_lookup_');
      try {
        manager.setCachePath(p.join(tempDir.path, 'metadata_cache.json'));
        manager.setFeatureFlags(
          const AriamiFeatureFlags(enableCatalogRead: true),
        );
        final repository = manager.createCatalogRepository()!;
        repository.upsertSong(CatalogSongRecord(
          id: 'catalog-song',
          filePath: '/music/catalog-song.mp3',
          title: 'Catalog Song',
          artist: 'Catalog Artist',
          durationSeconds: 211,
          bitrateKbps: 128,
          updatedToken: 1,
        ));

        manager.setLibraryForTesting(null);

        expect(
            manager.getSongFilePath('catalog-song'), '/music/catalog-song.mp3');
        expect(manager.getKnownSongDuration('catalog-song'), 211);
        expect(manager.getKnownSongBitrate('catalog-song'), 128);
      } finally {
        manager.clear();
        await tempDir.delete(recursive: true);
      }
    });
  });
}

LibraryStructure _largeLibrary({
  required int albumCount,
  required int songsPerAlbum,
  required int standaloneCount,
}) {
  final albums = <String, Album>{};

  for (var albumIndex = 0; albumIndex < albumCount; albumIndex++) {
    final albumId = 'album_${albumIndex.toString().padLeft(3, '0')}';
    final songs = <SongMetadata>[];

    for (var songIndex = 0; songIndex < songsPerAlbum; songIndex++) {
      songs.add(SongMetadata(
        filePath:
            '/music/$albumId/track_${songIndex.toString().padLeft(3, '0')}.mp3',
        title: 'Track $songIndex',
        artist: 'Artist $albumIndex',
        album: 'Album $albumIndex',
        duration: 180 + songIndex,
        bitrate: songIndex.isEven ? 96 : 192,
      ));
    }

    albums[albumId] = Album(
      id: albumId,
      title: 'Album $albumIndex',
      artist: 'Artist $albumIndex',
      songs: songs,
    );
  }

  final standaloneSongs = <SongMetadata>[];
  for (var songIndex = 0; songIndex < standaloneCount; songIndex++) {
    standaloneSongs.add(SongMetadata(
      filePath:
          '/music/standalone/track_${songIndex.toString().padLeft(3, '0')}.mp3',
      title: 'Standalone $songIndex',
      artist: 'Standalone Artist',
      duration: 200 + (songIndex % 20),
      bitrate: 128,
    ));
  }

  return LibraryStructure(
    albums: albums,
    standaloneSongs: standaloneSongs,
  );
}

String _songId(String filePath) {
  return md5.convert(utf8.encode(filePath)).toString().substring(0, 12);
}
