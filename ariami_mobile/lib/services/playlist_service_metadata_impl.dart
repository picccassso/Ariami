part of 'playlist_service.dart';

extension _PlaylistServiceMetadataImpl on PlaylistService {
  Future<_PlaylistSongMetadata> _buildPlaylistSongMetadata(
    List<String> songIds, {
    required List<SongModel> allSongs,
  }) async {
    final canonicalSongsById = await _buildCanonicalSongIndex(allSongs);
    return _buildPlaylistSongMetadataFromIndex(songIds, canonicalSongsById);
  }

  Future<Map<String, SongModel>> _buildCanonicalSongIndex(
    List<SongModel> allSongs,
  ) async {
    final songsById = <String, SongModel>{};

    void mergeSong(SongModel song) {
      final existing = songsById[song.id];
      if (existing == null) {
        songsById[song.id] = song;
        return;
      }

      final existingScore = _songMetadataScore(existing);
      final candidateScore = _songMetadataScore(song);
      if (candidateScore >= existingScore) {
        songsById[song.id] = song;
      }
    }

    for (final song in allSongs) {
      mergeSong(song);
    }

    try {
      final repositorySongs = await _loadCanonicalLibrarySongs();
      for (final song in repositorySongs) {
        mergeSong(song);
      }
    } catch (error) {
      print('[PlaylistService] Error loading canonical library songs: $error');
    }

    return songsById;
  }

  Future<List<SongModel>> _loadCanonicalLibrarySongs() async {
    try {
      return await _libraryRepository.getSongs();
    } catch (error) {
      if (!_isClosedDatabaseError(error)) {
        rethrow;
      }

      _libraryRepository = LibraryRepository();
      return _libraryRepository.getSongs();
    }
  }

  _PlaylistSongMetadata _buildPlaylistSongMetadataFromIndex(
    List<String> songIds,
    Map<String, SongModel> songsById,
  ) {
    final songAlbumIds = <String, String>{};
    final songTitles = <String, String>{};
    final songArtists = <String, String>{};
    final songDurations = <String, int>{};

    for (final songId in songIds) {
      final song = songsById[songId];
      if (song == null) {
        continue;
      }
      if (song.albumId != null) {
        songAlbumIds[songId] = song.albumId!;
      }
      songTitles[songId] = song.title;
      songArtists[songId] = song.artist;
      songDurations[songId] = song.duration;
    }

    return _PlaylistSongMetadata(
      songAlbumIds: songAlbumIds,
      songTitles: songTitles,
      songArtists: songArtists,
      songDurations: songDurations,
    );
  }

  int _songMetadataScore(SongModel song) {
    var score = 0;
    if (song.duration > 0) score += 4;
    if (song.albumId != null && song.albumId!.isNotEmpty) score += 2;
    if (song.title.isNotEmpty && song.title != 'Unknown Song') score += 1;
    if (song.artist.isNotEmpty && song.artist != 'Unknown Artist') score += 1;
    return score;
  }

  bool _isClosedDatabaseError(Object error) {
    return error.toString().contains('database has already been closed');
  }

  Future<int> _rehydrateAlbumIdsFromLibraryImpl(
    List<SongModel> librarySongs,
  ) async {
    return _rehydrateSongMetadataFromLibrary(
      librarySongs,
      updateTitles: false,
      updateArtists: false,
      updateDurations: false,
    );
  }

  Future<int> _rehydrateSongMetadataFromLibraryImpl(
    List<SongModel> librarySongs,
  ) async {
    return _rehydrateSongMetadataFromLibrary(librarySongs);
  }

  Future<int> _remapPlaylistSongIdsImpl(List<SongModel> librarySongs) async {
    if (!_isLoaded) await loadPlaylists();
    if (_playlists.isEmpty || librarySongs.isEmpty) return 0;

    final remappingService = SongIdRemappingService();
    final remapped = remappingService.remapPlaylists(_playlists, librarySongs);

    var changedCount = 0;
    for (var index = 0; index < _playlists.length; index++) {
      if (!identical(_playlists[index], remapped[index])) {
        changedCount++;
      }
    }

    if (changedCount > 0) {
      _playlists = remapped;
      await _savePlaylists();
      _notifyListeners();
      print(
        '[PlaylistService] Remapped stale song IDs in $changedCount playlists',
      );
    }

    return changedCount;
  }

  Future<int> _rehydrateSongMetadataFromLibrary(
    List<SongModel> librarySongs, {
    bool updateTitles = true,
    bool updateArtists = true,
    bool updateDurations = true,
  }) async {
    if (!_isLoaded) {
      await loadPlaylists();
    }

    final songsById = <String, SongModel>{};
    for (final song in librarySongs) {
      songsById[song.id] = song;
    }

    if (songsById.isEmpty || _playlists.isEmpty) {
      return 0;
    }

    var updatedCount = 0;
    final updatedPlaylists = <PlaylistModel>[];

    for (final playlist in _playlists) {
      var changed = false;
      final updatedSongAlbumIds =
          Map<String, String>.from(playlist.songAlbumIds);
      final updatedSongTitles = Map<String, String>.from(playlist.songTitles);
      final updatedSongArtists = Map<String, String>.from(playlist.songArtists);
      final updatedSongDurations =
          Map<String, int>.from(playlist.songDurations);

      for (final songId in playlist.songIds) {
        final song = songsById[songId];
        if (song == null) continue;

        final albumId = song.albumId;
        if (albumId != null && albumId.isNotEmpty) {
          if (updatedSongAlbumIds[songId] != albumId) {
            updatedSongAlbumIds[songId] = albumId;
            changed = true;
          }
        } else if (updatedSongAlbumIds.containsKey(songId)) {
          // Remove stale album mappings so standalone songs use song artwork.
          updatedSongAlbumIds.remove(songId);
          changed = true;
        }

        if (updateTitles &&
            song.title.isNotEmpty &&
            updatedSongTitles[songId] != song.title) {
          updatedSongTitles[songId] = song.title;
          changed = true;
        }

        if (updateArtists &&
            song.artist.isNotEmpty &&
            updatedSongArtists[songId] != song.artist) {
          updatedSongArtists[songId] = song.artist;
          changed = true;
        }

        if (updateDurations &&
            song.duration > 0 &&
            updatedSongDurations[songId] != song.duration) {
          updatedSongDurations[songId] = song.duration;
          changed = true;
        }
      }

      if (changed) {
        updatedCount++;
        updatedPlaylists.add(
          playlist.copyWith(
            songAlbumIds: updatedSongAlbumIds,
            songTitles: updatedSongTitles,
            songArtists: updatedSongArtists,
            songDurations: updatedSongDurations,
            modifiedAt: DateTime.now(),
          ),
        );
      } else {
        updatedPlaylists.add(playlist);
      }
    }

    if (updatedCount > 0) {
      _playlists = updatedPlaylists;
      await _savePlaylists();
      _notifyListeners();
    }

    return updatedCount;
  }
}

class _PlaylistSongMetadata {
  const _PlaylistSongMetadata({
    required this.songAlbumIds,
    required this.songTitles,
    required this.songArtists,
    required this.songDurations,
  });

  final Map<String, String> songAlbumIds;
  final Map<String, String> songTitles;
  final Map<String, String> songArtists;
  final Map<String, int> songDurations;
}
