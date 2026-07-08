import 'package:ariami_core/models/file_change.dart';
import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/library/album_builder.dart';
import 'package:ariami_core/services/library/change_processor.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:test/test.dart';

SongMetadata _song({
  required String path,
  String? album,
  String? title,
  String? artist,
  String? albumArtist,
}) {
  return SongMetadata(
    filePath: path,
    album: album,
    title: title,
    artist: artist,
    albumArtist: albumArtist,
  );
}

String _songId(String filePath) => defaultGenerateSongId(filePath);

LibraryStructure _libraryWithAlbumAndPlaylist({
  required String albumSong1Path,
  required String albumSong2Path,
  required String playlistFolderPath,
  required String playlistSongPath,
}) {
  final albumSongs = [
    _song(
      path: albumSong1Path,
      album: 'Test Album',
      artist: 'Test Artist',
      title: 'One',
    ),
    _song(
      path: albumSong2Path,
      album: 'Test Album',
      artist: 'Test Artist',
      title: 'Two',
    ),
  ];
  final playlistSong = _song(
    path: playlistSongPath,
    title: 'Playlist Track',
    artist: 'Guest',
  );

  final baseLibrary = AlbumBuilder().buildLibrary(albumSongs);
  final playlist = FolderPlaylist(
    id: FolderPlaylist.generateId(playlistFolderPath),
    name: FolderPlaylist.extractName('[PLAYLIST] Summer'),
    folderPath: playlistFolderPath,
    songIds: [_songId(playlistSongPath)],
  );

  return LibraryStructure(
    albums: baseLibrary.albums,
    standaloneSongs: [playlistSong],
    folderPlaylists: [playlist],
  );
}

void main() {
  group('ChangeProcessor.applyUpdates', () {
    late ChangeProcessor processor;

    setUp(() {
      processor = ChangeProcessor();
    });

    test('preserves folderPlaylists when adding unrelated song', () async {
      const playlistFolder = '/music/[PLAYLIST] Summer';
      const playlistSongPath = '$playlistFolder/track1.mp3';
      final currentLibrary = _libraryWithAlbumAndPlaylist(
        albumSong1Path: '/music/album/one.mp3',
        albumSong2Path: '/music/album/two.mp3',
        playlistFolderPath: playlistFolder,
        playlistSongPath: playlistSongPath,
      );

      const newSongPath = '/music/standalone/new.mp3';
      final newSong = _song(path: newSongPath, title: 'New Song');
      final update = LibraryUpdate(
        addedSongIds: {_songId(newSongPath)},
        removedSongIds: {},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
        extractedMetadata: {newSongPath: newSong},
      );

      final updatedLibrary = await processor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: [
          FileChange(
            path: newSongPath,
            type: FileChangeType.added,
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(updatedLibrary.folderPlaylists, hasLength(1));
      expect(updatedLibrary.folderPlaylists.first.id,
          currentLibrary.folderPlaylists.first.id);
      expect(updatedLibrary.folderPlaylists.first.songIds,
          currentLibrary.folderPlaylists.first.songIds);
      expect(
        updatedLibrary.standaloneSongs.any((song) => song.filePath == newSongPath),
        isTrue,
      );
    });

    test('updates playlist when song is added inside playlist folder', () async {
      const playlistFolder = '/music/[PLAYLIST] Summer';
      const existingTrackPath = '$playlistFolder/track1.mp3';
      const addedTrackPath = '$playlistFolder/track2.mp3';
      final currentLibrary = _libraryWithAlbumAndPlaylist(
        albumSong1Path: '/music/album/one.mp3',
        albumSong2Path: '/music/album/two.mp3',
        playlistFolderPath: playlistFolder,
        playlistSongPath: existingTrackPath,
      );

      final addedSong = _song(path: addedTrackPath, title: 'Track 2');
      final update = LibraryUpdate(
        addedSongIds: {_songId(addedTrackPath)},
        removedSongIds: {},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
        extractedMetadata: {addedTrackPath: addedSong},
      );

      final updatedLibrary = await processor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: [
          FileChange(
            path: addedTrackPath,
            type: FileChangeType.added,
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(updatedLibrary.folderPlaylists, hasLength(1));
      expect(
        updatedLibrary.folderPlaylists.first.songIds,
        containsAll([_songId(existingTrackPath), _songId(addedTrackPath)]),
      );
      expect(updatedLibrary.folderPlaylists.first.songCount, 2);
    });

    test('removes song from playlist when file is deleted', () async {
      const playlistFolder = '/music/[PLAYLIST] Summer';
      const remainingTrackPath = '$playlistFolder/track1.mp3';
      const removedTrackPath = '$playlistFolder/track2.mp3';
      final currentLibrary = _libraryWithAlbumAndPlaylist(
        albumSong1Path: '/music/album/one.mp3',
        albumSong2Path: '/music/album/two.mp3',
        playlistFolderPath: playlistFolder,
        playlistSongPath: remainingTrackPath,
      );

      final playlistWithTwoTracks = FolderPlaylist(
        id: currentLibrary.folderPlaylists.first.id,
        name: currentLibrary.folderPlaylists.first.name,
        folderPath: playlistFolder,
        songIds: [
          _songId(remainingTrackPath),
          _songId(removedTrackPath),
        ],
      );
      final libraryWithTwoPlaylistTracks = LibraryStructure(
        albums: currentLibrary.albums,
        standaloneSongs: [
          ...currentLibrary.standaloneSongs,
          _song(path: removedTrackPath, title: 'Track 2'),
        ],
        folderPlaylists: [playlistWithTwoTracks],
      );

      final update = LibraryUpdate(
        addedSongIds: {},
        removedSongIds: {_songId(removedTrackPath)},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
      );

      final updatedLibrary = await processor.applyUpdates(
        update,
        libraryWithTwoPlaylistTracks,
      );

      expect(updatedLibrary.folderPlaylists, hasLength(1));
      expect(updatedLibrary.folderPlaylists.first.songIds,
          [_songId(remainingTrackPath)]);
    });

    test('detects new playlist folder from added song path', () async {
      const newPlaylistFolder = '/music/[PLAYLIST] Fresh Mix';
      const newTrackPath = '$newPlaylistFolder/song.mp3';
      final currentLibrary = _libraryWithAlbumAndPlaylist(
        albumSong1Path: '/music/album/one.mp3',
        albumSong2Path: '/music/album/two.mp3',
        playlistFolderPath: '/music/[PLAYLIST] Old',
        playlistSongPath: '/music/[PLAYLIST] Old/track.mp3',
      );

      final newSong = _song(path: newTrackPath, title: 'Fresh');
      final update = LibraryUpdate(
        addedSongIds: {_songId(newTrackPath)},
        removedSongIds: {},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
        extractedMetadata: {newTrackPath: newSong},
      );

      final updatedLibrary = await processor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: [
          FileChange(
            path: newTrackPath,
            type: FileChangeType.added,
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(updatedLibrary.folderPlaylists, hasLength(2));
      expect(
        updatedLibrary.folderPlaylists
            .any((playlist) => playlist.folderPath == newPlaylistFolder),
        isTrue,
      );
    });

    test('lets playlist songs join album grouping (additive membership)',
        () async {
      const playlistFolder = '/music/[PLAYLIST] Compilations';
      const playlistSongPath = '$playlistFolder/track.mp3';
      final playlistSong = _song(
        path: playlistSongPath,
        album: 'Shared Album Title',
        artist: 'Artist A',
        title: 'Track',
      );
      final albumSong1 = _song(
        path: '/music/album/one.mp3',
        album: 'Shared Album Title',
        artist: 'Artist A',
        title: 'One',
      );
      final albumSong2 = _song(
        path: '/music/album/two.mp3',
        album: 'Shared Album Title',
        artist: 'Artist A',
        title: 'Two',
      );

      final baseLibrary = AlbumBuilder().buildLibrary([albumSong1, albumSong2]);
      final currentLibrary = LibraryStructure(
        albums: baseLibrary.albums,
        standaloneSongs: [playlistSong],
        folderPlaylists: [
          FolderPlaylist(
            id: FolderPlaylist.generateId(playlistFolder),
            name: 'Compilations',
            folderPath: playlistFolder,
            songIds: [_songId(playlistSongPath)],
          ),
        ],
      );

      const newSongPath = '/music/other/new.mp3';
      final newSong = _song(path: newSongPath, title: 'Other');
      final update = LibraryUpdate(
        addedSongIds: {_songId(newSongPath)},
        removedSongIds: {},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
        extractedMetadata: {newSongPath: newSong},
      );

      final updatedLibrary = await processor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: [
          FileChange(
            path: newSongPath,
            type: FileChangeType.added,
            timestamp: DateTime.now(),
          ),
        ],
      );

      // The playlist track shares album tags with the album songs, so it now
      // joins the album while still appearing in its folder playlist.
      expect(updatedLibrary.albums.length, 1);
      expect(updatedLibrary.albums.values.first.songs.length, 3);
      expect(
        updatedLibrary.albums.values.first.songs
            .any((song) => song.filePath == playlistSongPath),
        isTrue,
      );
      expect(
        updatedLibrary.standaloneSongs
            .any((song) => song.filePath == playlistSongPath),
        isFalse,
      );
      expect(updatedLibrary.folderPlaylists, hasLength(1));
      expect(
        updatedLibrary.folderPlaylists.first.songIds,
        contains(_songId(playlistSongPath)),
      );
    });

    group('deduped playlist entries', () {
      const playlistFolder = '/music/[PLAYLIST] Summer';
      const canonicalPath = '/music/album/one.mp3';
      const dedupedCopyPath = '$playlistFolder/one-copy.mp3';

      LibraryStructure libraryWithDedupedPlaylistCopy() {
        final baseLibrary = AlbumBuilder().buildLibrary([
          _song(
            path: canonicalPath,
            album: 'Test Album',
            artist: 'Test Artist',
            title: 'One',
          ),
          _song(
            path: '/music/album/two.mp3',
            album: 'Test Album',
            artist: 'Test Artist',
            title: 'Two',
          ),
        ]);
        // Mirrors a full scan where the playlist folder held a byte-identical
        // copy of one.mp3: the copy was filtered, the playlist entry was
        // remapped to the canonical song ID, and the mapping was recorded.
        return LibraryStructure(
          albums: baseLibrary.albums,
          standaloneSongs: const [],
          folderPlaylists: [
            FolderPlaylist(
              id: FolderPlaylist.generateId(playlistFolder),
              name: 'Summer',
              folderPath: playlistFolder,
              songIds: [_songId(canonicalPath)],
            ),
          ],
          duplicateToOriginalPath: const {dedupedCopyPath: canonicalPath},
        );
      }

      test('survive an unrelated incremental rebuild', () async {
        final currentLibrary = libraryWithDedupedPlaylistCopy();

        const newSongPath = '/music/standalone/new.mp3';
        final update = LibraryUpdate(
          addedSongIds: {_songId(newSongPath)},
          removedSongIds: {},
          modifiedSongIds: {},
          affectedAlbumIds: {},
          timestamp: DateTime.now(),
          extractedMetadata: {
            newSongPath: _song(path: newSongPath, title: 'New Song'),
          },
        );

        final updatedLibrary = await processor.applyUpdates(
          update,
          currentLibrary,
          sourceChanges: [
            FileChange(
              path: newSongPath,
              type: FileChangeType.added,
              timestamp: DateTime.now(),
            ),
          ],
        );

        expect(updatedLibrary.folderPlaylists, hasLength(1));
        expect(
          updatedLibrary.folderPlaylists.first.songIds,
          [_songId(canonicalPath)],
          reason: 'the deduped playlist copy must keep referencing the '
              'canonical song ID after an incremental rebuild',
        );
        expect(
          updatedLibrary.duplicateToOriginalPath,
          {dedupedCopyPath: canonicalPath},
          reason: 'the mapping must survive for subsequent rebuilds',
        );
      });

      test('are dropped when the deduped copy file is removed', () async {
        final currentLibrary = libraryWithDedupedPlaylistCopy();

        final update = LibraryUpdate(
          addedSongIds: {},
          removedSongIds: {_songId(dedupedCopyPath)},
          modifiedSongIds: {},
          affectedAlbumIds: {},
          timestamp: DateTime.now(),
        );

        final updatedLibrary = await processor.applyUpdates(
          update,
          currentLibrary,
          sourceChanges: [
            FileChange(
              path: dedupedCopyPath,
              type: FileChangeType.removed,
              timestamp: DateTime.now(),
            ),
          ],
        );

        // The copy was the playlist's only entry; like a full scan, an empty
        // playlist folder yields no playlist.
        expect(updatedLibrary.folderPlaylists, isEmpty,
            reason: 'deleting the folder copy removes the playlist entry');
        expect(updatedLibrary.duplicateToOriginalPath, isEmpty);
        // The canonical album song itself is untouched.
        expect(updatedLibrary.albums.values.single.songs.length, 2);
      });

      test('are dropped when the canonical original is removed', () async {
        final currentLibrary = libraryWithDedupedPlaylistCopy();

        final update = LibraryUpdate(
          addedSongIds: {},
          removedSongIds: {_songId(canonicalPath)},
          modifiedSongIds: {},
          affectedAlbumIds: {},
          timestamp: DateTime.now(),
        );

        final updatedLibrary = await processor.applyUpdates(
          update,
          currentLibrary,
          sourceChanges: [
            FileChange(
              path: canonicalPath,
              type: FileChangeType.removed,
              timestamp: DateTime.now(),
            ),
          ],
        );

        expect(updatedLibrary.duplicateToOriginalPath, isEmpty,
            reason: 'a mapping to a removed original must not survive');
        // With the original gone the playlist has no resolvable entries left.
        expect(updatedLibrary.folderPlaylists, isEmpty);
      });
    });

    test('keeps folder playlist IDs stable across rebuilds', () async {
      const playlistFolder = '/music/[PLAYLIST] Summer';
      const playlistSongPath = '$playlistFolder/track1.mp3';
      final currentLibrary = _libraryWithAlbumAndPlaylist(
        albumSong1Path: '/music/album/one.mp3',
        albumSong2Path: '/music/album/two.mp3',
        playlistFolderPath: playlistFolder,
        playlistSongPath: playlistSongPath,
      );

      const newSongPath = '/music/other/new.mp3';
      final update = LibraryUpdate(
        addedSongIds: {_songId(newSongPath)},
        removedSongIds: {},
        modifiedSongIds: {},
        affectedAlbumIds: {},
        timestamp: DateTime.now(),
        extractedMetadata: {
          newSongPath: _song(path: newSongPath, title: 'Other'),
        },
      );

      final updatedLibrary = await processor.applyUpdates(
        update,
        currentLibrary,
        sourceChanges: [
          FileChange(
            path: newSongPath,
            type: FileChangeType.added,
            timestamp: DateTime.now(),
          ),
        ],
      );

      // Edit-store overlays and user playlist references are keyed by this
      // ID, so it must never drift during watcher updates.
      expect(
        updatedLibrary.folderPlaylists.single.id,
        FolderPlaylist.generateId(playlistFolder),
      );
    });
  });
}
