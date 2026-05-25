import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/album.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/catalog/catalog_writer.dart';
import 'package:test/test.dart';

void main() {
  group('CatalogWriter', () {
    late Directory tempDir;
    late CatalogDatabase catalogDatabase;
    late CatalogRepository repository;
    late CatalogWriter writer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_catalog_writer_');
      catalogDatabase =
          CatalogDatabase(databasePath: '${tempDir.path}/catalog.db');
      catalogDatabase.initialize();
      repository = CatalogRepository(database: catalogDatabase.database);
      writer = CatalogWriter(database: catalogDatabase.database);
    });

    tearDown(() async {
      catalogDatabase.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('preserves duplicate playlist songs as position-addressed rows', () {
      final library = LibraryStructure(
        albums: const {},
        standaloneSongs: const <SongMetadata>[
          SongMetadata(
            filePath: '/tmp/song-a.mp3',
            title: 'Song A',
            artist: 'Artist A',
            duration: 180,
          ),
        ],
        folderPlaylists: const <FolderPlaylist>[
          FolderPlaylist(
            id: 'playlist-1',
            name: 'Playlist 1',
            folderPath: '/tmp/playlist-1',
            songIds: <String>['song-a', 'song-a'],
          ),
        ],
      );

      writer.writeFullSnapshot(
        library: library,
        songIdForPath: (filePath) => 'song-a',
      );

      final playlistSongs = repository.listPlaylistSongs('playlist-1');
      expect(
        playlistSongs.map((item) => item.songId).toList(),
        equals(<String>['song-a', 'song-a']),
      );
      expect(
        playlistSongs.map((item) => item.position).toList(),
        equals(<int>[0, 1]),
      );

      final events = repository
          .readChangesSince(0, 100)
          .where((event) => event.entityType == 'playlist_song')
          .toList();
      expect(
        events.map((event) => event.entityId).toList(),
        equals(<String>['playlist-1:0', 'playlist-1:1']),
      );
      expect(
        events
            .map((event) => jsonDecode(event.payloadJson!)['position'] as int)
            .toList(),
        equals(<int>[0, 1]),
      );

      final playlistEvents = repository
          .readChangesSince(0, 100)
          .where((event) => event.entityType == 'playlist')
          .toList();
      expect(
        jsonDecode(playlistEvents.single.payloadJson!)['duration'],
        equals(360),
      );
    });

    test('does not set coverArtKey when album hasArtwork is false', () {
      final library = LibraryStructure(
        albums: {
          'album-no-art': Album(
            id: 'album-no-art',
            title: 'No Art Album',
            artist: 'Artist',
            songs: const [
              SongMetadata(
                filePath: '/tmp/album/track1.mp3',
                title: 'Track 1',
                artist: 'Artist',
                album: 'No Art Album',
                duration: 180,
              ),
              SongMetadata(
                filePath: '/tmp/album/track2.mp3',
                title: 'Track 2',
                artist: 'Artist',
                album: 'No Art Album',
                duration: 180,
              ),
            ],
            artworkPath: '/tmp/album/track1.mp3',
            hasArtwork: false,
          ),
        },
        standaloneSongs: const [],
      );

      writer.writeFullSnapshot(
        library: library,
        songIdForPath: (path) => 'song-${path.hashCode}',
      );

      final album = repository.getAlbumsByIds(['album-no-art']).single;
      expect(album.coverArtKey, isNull);
    });

    test('sets coverArtKey when album hasArtwork is true', () {
      final library = LibraryStructure(
        albums: {
          'album-with-art': Album(
            id: 'album-with-art',
            title: 'Art Album',
            artist: 'Artist',
            songs: const [
              SongMetadata(
                filePath: '/tmp/art/track1.mp3',
                title: 'Track 1',
                artist: 'Artist',
                album: 'Art Album',
                duration: 180,
              ),
              SongMetadata(
                filePath: '/tmp/art/track2.mp3',
                title: 'Track 2',
                artist: 'Artist',
                album: 'Art Album',
                duration: 180,
              ),
            ],
            artworkPath: '/tmp/art/cover.jpg',
            hasArtwork: true,
          ),
        },
        standaloneSongs: const [],
      );

      writer.writeFullSnapshot(
        library: library,
        songIdForPath: (path) => 'song-${path.hashCode}',
      );

      final album = repository.getAlbumsByIds(['album-with-art']).single;
      expect(album.coverArtKey, 'album-with-art');
    });
  });
}
