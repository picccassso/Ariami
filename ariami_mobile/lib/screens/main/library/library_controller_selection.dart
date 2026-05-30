// ignore_for_file: avoid_print

part of 'library_controller.dart';

extension _LibraryControllerSelection on LibraryController {
  void _enterSelectionMode() {
    _isSelectionModeActive = true;
    _selectedPlaylistIds.clear();
    _selectedAlbumIds.clear();
    _selectedSongIds.clear();
    _notifyListeners();
  }

  void _exitSelectionMode() {
    _isSelectionModeActive = false;
    _selectedPlaylistIds.clear();
    _selectedAlbumIds.clear();
    _selectedSongIds.clear();
    _notifyListeners();
  }

  void _togglePlaylistSelection(String playlistId) {
    if (_selectedPlaylistIds.contains(playlistId)) {
      _selectedPlaylistIds.remove(playlistId);
    } else {
      _selectedPlaylistIds.add(playlistId);
    }
    _notifyListeners();
  }

  void _toggleAlbumSelection(String albumId) {
    if (_selectedAlbumIds.contains(albumId)) {
      _selectedAlbumIds.remove(albumId);
    } else {
      _selectedAlbumIds.add(albumId);
    }
    _notifyListeners();
  }

  void _toggleSongSelection(String songId) {
    if (_selectedSongIds.contains(songId)) {
      _selectedSongIds.remove(songId);
    } else {
      _selectedSongIds.add(songId);
    }
    _notifyListeners();
  }

  void _selectAllVisible() {
    for (final playlist in _playlistService.playlists) {
      _selectedPlaylistIds.add(playlist.id);
    }

    for (final album in _state.albumsToShow) {
      _selectedAlbumIds.add(album.id);
    }

    if (_state.isOfflineMode) {
      for (final song in _state.offlineSongs) {
        _selectedSongIds.add(song.id);
      }
    } else {
      for (final song in _state.onlineSongsToShow) {
        _selectedSongIds.add(song.id);
      }
    }

    _notifyListeners();
  }

  void _clearSelection() {
    _selectedPlaylistIds.clear();
    _selectedAlbumIds.clear();
    _selectedSongIds.clear();
    _notifyListeners();
  }

  Set<String> _resolveSelectedSongIds() {
    final resolvedSongIds = <String>{};
    resolvedSongIds.addAll(_selectedSongIds);

    for (final playlistId in _selectedPlaylistIds) {
      final localPlaylist = _playlistService.getPlaylist(playlistId);
      if (localPlaylist != null) {
        resolvedSongIds.addAll(localPlaylist.songIds);
      }
    }

    for (final albumId in _selectedAlbumIds) {
      final albumSongs =
          _state.songs.where((song) => song.albumId == albumId).map(
                (song) => song.id,
              );
      resolvedSongIds.addAll(albumSongs);
    }

    return resolvedSongIds;
  }

  bool _isSongInDownloadQueue(String songId) {
    if (_queuedSongIdsForTest != null) {
      return _queuedSongIdsForTest!.contains(songId);
    }
    return _downloadManager.queue.any((task) => task.songId == songId);
  }

  bool _isPlaylistFullyDownloaded(String playlistId) {
    final playlist = _playlistService.getPlaylist(playlistId);
    if (playlist == null || playlist.songIds.isEmpty) return false;
    return playlist.songIds.every(_state.isSongDownloaded);
  }

  ({List<String> albumIds, List<String> playlistIds})
      _filteredContainersForEnqueue() {
    final albumIds = _selectedAlbumIds
        .where((id) => !_state.isAlbumFullyDownloaded(id))
        .toList();

    final playlistIds = <String>[];
    for (final playlistId in _selectedPlaylistIds) {
      final localPlaylist = _playlistService.getPlaylist(playlistId);
      if (localPlaylist != null) {
        continue;
      }
      if (!_isPlaylistFullyDownloaded(playlistId)) {
        playlistIds.add(playlistId);
      }
    }

    return (albumIds: albumIds, playlistIds: playlistIds);
  }

  BatchDownloadSummary _computeBatchDownloadSummary() {
    final resolvedSongIds = _resolveSelectedSongIds();
    var alreadySavedCount = 0;
    var inQueueCount = 0;
    var toDownloadCount = 0;

    for (final songId in resolvedSongIds) {
      if (_state.isSongDownloaded(songId)) {
        alreadySavedCount++;
      } else if (_isSongInDownloadQueue(songId)) {
        inQueueCount++;
      } else {
        toDownloadCount++;
      }
    }

    final containers = _filteredContainersForEnqueue();
    final hasEnqueueTargets = toDownloadCount > 0 ||
        containers.albumIds.isNotEmpty ||
        containers.playlistIds.isNotEmpty;

    return BatchDownloadSummary(
      containerCount: totalSelectedCount,
      resolvedSongCount: resolvedSongIds.length,
      alreadySavedCount: alreadySavedCount,
      inQueueCount: inQueueCount,
      toDownloadCount: toDownloadCount,
      hasEnqueueTargets: hasEnqueueTargets,
    );
  }

  List<String> _songIdsNeedingDownload(Iterable<String> songIds) {
    return songIds
        .where(
          (id) => !_state.isSongDownloaded(id) && !_isSongInDownloadQueue(id),
        )
        .toList();
  }

  Future<int> _downloadSelectedItems() async {
    if (totalSelectedCount == 0) return 0;

    final summary = batchDownloadSummary;
    if (summary.allSaved) return 0;

    final resolvedSongIds = _resolveSelectedSongIds();
    final songIdsToEnqueue = _songIdsNeedingDownload(resolvedSongIds);
    final containers = _filteredContainersForEnqueue();
    final playlistIdsList = _selectedPlaylistIds.toList();

    exitSelectionMode();

    var count = 0;
    try {
      count = await _downloadManager.enqueueDownloadJob(
        songIds: songIdsToEnqueue,
        albumIds: containers.albumIds,
        playlistIds: containers.playlistIds,
      );
    } catch (e, stackTrace) {
      print(
        'DownloadManager enqueueDownloadJob failed, falling back to local '
        'resolver: $e\n$stackTrace',
      );

      final allFallbackSongIds = <String>{...songIdsToEnqueue};

      for (final albumId in containers.albumIds) {
        final albumSongs =
            _state.songs.where((song) => song.albumId == albumId).map(
                  (song) => song.id,
                );
        allFallbackSongIds.addAll(_songIdsNeedingDownload(albumSongs));
      }

      for (final songId in allFallbackSongIds) {
        final songMatch = _state.songs.where((song) => song.id == songId);

        String? title;
        String? artist;
        String? albumId;
        var duration = 0;
        int? trackNumber;

        if (songMatch.isNotEmpty) {
          final song = songMatch.first;
          title = song.title;
          artist = song.artist;
          albumId = song.albumId;
          duration = song.duration;
          trackNumber = song.trackNumber;
        } else {
          for (final playlistId in playlistIdsList) {
            final localPlaylist = _playlistService.getPlaylist(playlistId);
            if (localPlaylist != null &&
                localPlaylist.songIds.contains(songId)) {
              title = localPlaylist.songTitles[songId];
              artist = localPlaylist.songArtists[songId];
              albumId = localPlaylist.songAlbumIds[songId];
              duration = localPlaylist.songDurations[songId] ?? 0;
              break;
            }
          }
        }

        title ??= 'Song $songId';
        artist ??= 'Unknown Artist';

        String? albumName;
        String? albumArtist;
        if (albumId != null) {
          final albumMatch =
              _state.albums.where((album) => album.id == albumId);
          if (albumMatch.isNotEmpty) {
            albumName = albumMatch.first.title;
            albumArtist = albumMatch.first.artist;
          }
        }

        final baseUrl = _connectionService.apiClient?.baseUrl;
        final albumArt = (albumId != null && baseUrl != null)
            ? '$baseUrl/artwork/$albumId'
            : '';

        try {
          await _downloadManager.downloadSong(
            songId: songId,
            title: title,
            artist: artist,
            albumId: albumId,
            albumName: albumName,
            albumArtist: albumArtist,
            albumArt: albumArt,
            duration: duration,
            trackNumber: trackNumber,
            totalBytes: 0,
          );
          count++;
        } catch (downloadError) {
          print(
            'Failed to enqueue fallback download for song $songId: '
            '$downloadError',
          );
        }
      }
    }

    return count;
  }
}

/// Summary of what a multi-select batch download would enqueue.
class BatchDownloadSummary {
  const BatchDownloadSummary({
    required this.containerCount,
    required this.resolvedSongCount,
    required this.alreadySavedCount,
    required this.inQueueCount,
    required this.toDownloadCount,
    required this.hasEnqueueTargets,
  });

  final int containerCount;
  final int resolvedSongCount;
  final int alreadySavedCount;
  final int inQueueCount;
  final int toDownloadCount;
  final bool hasEnqueueTargets;

  bool get allSaved => !hasEnqueueTargets;

  bool get hasPartialSkip =>
      (alreadySavedCount + inQueueCount) > 0 && toDownloadCount > 0;
}
