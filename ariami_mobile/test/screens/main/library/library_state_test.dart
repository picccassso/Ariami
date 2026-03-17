import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/screens/main/library/library_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryState', () {
    test('should create default state', () {
      const state = LibraryState();

      expect(state.albums, isEmpty);
      expect(state.songs, isEmpty);
      expect(state.offlineSongs, isEmpty);
      expect(state.isOfflineMode, false);
      expect(state.isLoading, true);
      expect(state.errorMessage, isNull);
      expect(state.isGridView, true);
      expect(state.albumsExpanded, true);
      expect(state.songsExpanded, false);
      expect(state.showDownloadedOnly, false);
      expect(state.downloadedSongIds, isEmpty);
      expect(state.cachedSongIds, isEmpty);
      expect(state.albumsWithDownloads, isEmpty);
      expect(state.fullyDownloadedAlbumIds, isEmpty);
      expect(state.playlistsWithDownloads, isEmpty);
    });

    test('copyWith should create modified copy', () {
      const state = LibraryState();
      final newState = state.copyWith(
        isLoading: false,
        isGridView: false,
        albumsExpanded: false,
      );

      expect(newState.isLoading, false);
      expect(newState.isGridView, false);
      expect(newState.albumsExpanded, false);
      // Unchanged values should remain
      expect(newState.songsExpanded, state.songsExpanded);
      expect(newState.isOfflineMode, state.isOfflineMode);
    });

    test('copyWith with clearError should clear error message', () {
      final state = const LibraryState().copyWith(
        errorMessage: 'Some error',
      );
      expect(state.errorMessage, 'Some error');

      final newState = state.copyWith(clearError: true);
      expect(newState.errorMessage, isNull);
    });

    test('isLibraryEmpty should be true when no content', () {
      const state = LibraryState();
      expect(state.isLibraryEmpty, true);
    });

    test('isLibraryEmpty should be false when albums exist', () {
      final state = const LibraryState().copyWith(
        albums: [
          AlbumModel(
            id: 'album-1',
            title: 'Test Album',
            artist: 'Test Artist',
            songCount: 10,
            duration: 3600,
          ),
        ],
      );
      expect(state.isLibraryEmpty, false);
    });

    test('isLibraryEmpty should be false when online songs exist', () {
      final state = const LibraryState().copyWith(
        songs: [
          SongModel(
            id: 'song-1',
            title: 'Test Song',
            artist: 'Test Artist',
            duration: 180,
          ),
        ],
      );
      expect(state.isLibraryEmpty, false);
    });

    test('isLibraryEmpty should be false when offline songs exist', () {
      final state = const LibraryState().copyWith(
        isOfflineMode: true,
        offlineSongs: [
          Song(
            id: 'song-1',
            title: 'Test Song',
            artist: 'Test Artist',
            duration: const Duration(seconds: 180),
            filePath: '/test/path.mp3',
            fileSize: 1000,
            modifiedTime: DateTime.now(),
          ),
        ],
      );
      expect(state.isLibraryEmpty, false);
    });

    test('albumsToShow should return all albums when not filtering', () {
      final albums = [
        AlbumModel(
            id: '1',
            title: 'Album 1',
            artist: 'Artist',
            songCount: 5,
            duration: 100),
        AlbumModel(
            id: '2',
            title: 'Album 2',
            artist: 'Artist',
            songCount: 5,
            duration: 100),
      ];
      final state = const LibraryState().copyWith(albums: albums);

      expect(state.albumsToShow.length, 2);
    });

    test(
        'albumsToShow should filter by downloads when showDownloadedOnly is true',
        () {
      final albums = [
        AlbumModel(
            id: '1',
            title: 'Album 1',
            artist: 'Artist',
            songCount: 5,
            duration: 100),
        AlbumModel(
            id: '2',
            title: 'Album 2',
            artist: 'Artist',
            songCount: 5,
            duration: 100),
      ];
      final state = const LibraryState().copyWith(
        albums: albums,
        showDownloadedOnly: true,
        albumsWithDownloads: {'1'},
      );

      expect(state.albumsToShow.length, 1);
      expect(state.albumsToShow.first.id, '1');
    });

    test('onlineSongsToShow should return all songs when not filtering', () {
      final songs = [
        SongModel(id: '1', title: 'Song 1', artist: 'Artist', duration: 100),
        SongModel(id: '2', title: 'Song 2', artist: 'Artist', duration: 100),
      ];
      final state = const LibraryState().copyWith(songs: songs);

      expect(state.onlineSongsToShow.length, 2);
    });

    test(
        'onlineSongsToShow should filter by downloads when showDownloadedOnly is true',
        () {
      final songs = [
        SongModel(id: '1', title: 'Song 1', artist: 'Artist', duration: 100),
        SongModel(id: '2', title: 'Song 2', artist: 'Artist', duration: 100),
      ];
      final state = const LibraryState().copyWith(
        songs: songs,
        showDownloadedOnly: true,
        downloadedSongIds: {'1'},
      );

      expect(state.onlineSongsToShow.length, 1);
      expect(state.onlineSongsToShow.first.id, '1');
    });

    test('hasAlbumDownloads should return correct value', () {
      final state = const LibraryState().copyWith(
        albumsWithDownloads: {'album-1', 'album-2'},
      );

      expect(state.hasAlbumDownloads('album-1'), true);
      expect(state.hasAlbumDownloads('album-3'), false);
    });

    test('isAlbumFullyDownloaded should return correct value', () {
      final state = const LibraryState().copyWith(
        fullyDownloadedAlbumIds: {'album-1'},
      );

      expect(state.isAlbumFullyDownloaded('album-1'), true);
      expect(state.isAlbumFullyDownloaded('album-2'), false);
    });

    test('isSongDownloaded should return correct value', () {
      final state = const LibraryState().copyWith(
        downloadedSongIds: {'song-1', 'song-2'},
      );

      expect(state.isSongDownloaded('song-1'), true);
      expect(state.isSongDownloaded('song-3'), false);
    });

    test('isSongCached should return correct value', () {
      final state = const LibraryState().copyWith(
        cachedSongIds: {'song-1'},
      );

      expect(state.isSongCached('song-1'), true);
      expect(state.isSongCached('song-2'), false);
    });

    test('hasPlaylistDownloads should return correct value', () {
      final state = const LibraryState().copyWith(
        playlistsWithDownloads: {'playlist-1'},
      );

      expect(state.hasPlaylistDownloads('playlist-1'), true);
      expect(state.hasPlaylistDownloads('playlist-2'), false);
    });

    test('two identical states should be equal', () {
      const state1 = LibraryState(
        isLoading: false,
        isGridView: false,
      );
      const state2 = LibraryState(
        isLoading: false,
        isGridView: false,
      );

      expect(state1, state2);
      expect(state1.hashCode, state2.hashCode);
    });

    test('two different states should not be equal', () {
      const state1 = LibraryState(isLoading: true);
      const state2 = LibraryState(isLoading: false);

      expect(state1, isNot(state2));
    });

    test('toString should return meaningful representation', () {
      const state = LibraryState();
      final str = state.toString();

      expect(str, contains('LibraryState'));
      expect(str, contains('albums:'));
      expect(str, contains('songs:'));
      expect(str, contains('isLoading:'));
    });
  });

  group('setEquals', () {
    test('should return true for equal sets', () {
      expect(setEquals({'a', 'b'}, {'b', 'a'}), true);
    });

    test('should return false for different sized sets', () {
      expect(setEquals({'a'}, {'a', 'b'}), false);
    });

    test('should return false for different content', () {
      expect(setEquals({'a'}, {'b'}), false);
    });

    test('should return true for both null', () {
      expect(setEquals<String>(null, null), true);
    });

    test('should return false when one is null', () {
      expect(setEquals({'a'}, null), false);
      expect(setEquals(null, {'a'}), false);
    });
  });
}
