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

  /// Ids in [playlist] that resolve nowhere: not in the library and not
  /// downloaded. Downloaded copies stay playable even when the server no
  /// longer has the song, so they are never treated as removable.
  List<String> _unavailableSongIds(
    PlaylistModel playlist,
    Set<String> libraryIds,
    Set<String> downloadedSongIds,
  ) {
    return playlist.songIds
        .where((id) =>
            !libraryIds.contains(id) && !downloadedSongIds.contains(id))
        .toList(growable: false);
  }

  Future<UnavailableSongCleanupReport> _previewUnavailableSongCleanupImpl({
    required List<SongModel> librarySongs,
    required Set<String> downloadedSongIds,
  }) async {
    if (!_isLoaded) await loadPlaylists();
    if (librarySongs.isEmpty) {
      return const UnavailableSongCleanupReport(playlistCount: 0, songCount: 0);
    }

    // Heal what can heal first: entries whose id churned but whose metadata
    // still matches a library song must not be counted as unavailable.
    await _remapPlaylistSongIdsImpl(librarySongs);

    final libraryIds = {for (final song in librarySongs) song.id};
    var playlistCount = 0;
    var songCount = 0;
    for (final playlist in _playlists) {
      final removable =
          _unavailableSongIds(playlist, libraryIds, downloadedSongIds);
      if (removable.isEmpty) continue;
      playlistCount++;
      songCount += removable.length;
    }
    return UnavailableSongCleanupReport(
      playlistCount: playlistCount,
      songCount: songCount,
    );
  }

  Future<UnavailableSongCleanupReport> _removeUnavailableSongsImpl({
    required List<SongModel> librarySongs,
    required Set<String> downloadedSongIds,
  }) async {
    if (!_isLoaded) await loadPlaylists();
    if (librarySongs.isEmpty) {
      return const UnavailableSongCleanupReport(playlistCount: 0, songCount: 0);
    }

    await _remapPlaylistSongIdsImpl(librarySongs);

    final libraryIds = {for (final song in librarySongs) song.id};
    final changedPlaylistIds = <String>[];
    var songCount = 0;

    for (var index = 0; index < _playlists.length; index++) {
      final playlist = _playlists[index];
      final removable =
          _unavailableSongIds(playlist, libraryIds, downloadedSongIds)
              .toSet();
      if (removable.isEmpty) continue;

      final updatedSongIds = playlist.songIds
          .where((id) => !removable.contains(id))
          .toList(growable: false);
      _playlists[index] = playlist.copyWith(
        songIds: updatedSongIds,
        modifiedAt: DateTime.now(),
      );
      changedPlaylistIds.add(playlist.id);
      songCount += removable.length;
    }

    if (changedPlaylistIds.isEmpty) {
      return const UnavailableSongCleanupReport(playlistCount: 0, songCount: 0);
    }

    await _savePlaylists();
    _notifyListeners();
    for (final playlistId in changedPlaylistIds) {
      unawaited(_pushImportedPlaylistEditImpl(playlistId));
    }
    print(
      '[PlaylistService] Removed $songCount unavailable songs from '
      '${changedPlaylistIds.length} playlists',
    );

    return UnavailableSongCleanupReport(
      playlistCount: changedPlaylistIds.length,
      songCount: songCount,
    );
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
