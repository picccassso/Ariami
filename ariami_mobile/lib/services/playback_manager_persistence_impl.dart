part of 'playback_manager.dart';

extension _PlaybackManagerPersistenceImpl on PlaybackManager {
  Future<void> _saveStateImpl() async {
    // Skip if queue is empty
    if (_queue.isEmpty) return;

    // Get original queue if shuffled
    List<Song>? originalQueue;
    if (_isShuffleEnabled && _shuffleService.originalQueue.isNotEmpty) {
      originalQueue = _shuffleService.originalQueue.cast<Song>();
    }

    // Save state to persistent storage
    await _stateManager.saveCompletePlaybackState(
      queue: _queue,
      isShuffleEnabled: _isShuffleEnabled,
      repeatMode: _repeatMode,
      position: position,
      originalQueue: originalQueue,
    );
  }

  Future<void> _saveStateImmediatelyImpl() async {
    await _saveState();
  }

  Future<void> _restoreStateImpl() async {
    final restoreGeneration = _restoreGeneration;
    try {
      final savedState = await _stateManager.loadCompletePlaybackState();
      if (savedState == null) return;

      final restoredSongs = await _rehydrateSongs(savedState.queue.songs);
      final restoredQueue = PlaybackQueue(
        songs: restoredSongs,
        currentIndex: savedState.queue.currentIndex,
      );

      // Restore queue
      if (restoreGeneration != _restoreGeneration) {
        print(
          '[PlaybackManager] Skipping stale restore before queue apply: '
          'restoreGeneration=$restoreGeneration currentGeneration=$_restoreGeneration',
        );
        return;
      }
      _queue = restoredQueue;

      // Restore shuffle state and original queue
      _isShuffleEnabled = savedState.isShuffleEnabled;
      if (_isShuffleEnabled && savedState.originalQueue != null) {
        final restoredOriginalQueue =
            await _rehydrateSongs(savedState.originalQueue!);
        // Manually restore shuffle service state
        _shuffleService.enableShuffle(
          restoredOriginalQueue,
          _queue.currentSong,
        );
      }

      // Restore repeat mode
      _repeatMode = savedState.repeatMode;

      // Store playback position to seek to when user presses play
      if (_queue.currentSong != null && savedState.position > Duration.zero) {
        if (restoreGeneration != _restoreGeneration) {
          print(
            '[PlaybackManager] Skipping stale restore before position apply: '
            'restoreGeneration=$restoreGeneration currentGeneration=$_restoreGeneration',
          );
          return;
        }
        _restoredPosition = savedState.position;
        _pendingUiPosition = savedState.position;
      }

      _notifyStateChanged();
    } catch (e) {
      print('[PlaybackManager] Error restoring state: $e');
    }
  }

  void _invalidatePendingRestoreImpl(String reason) {
    _restoreGeneration++;
    print(
      '[PlaybackManager] Invalidated pending restore: '
      'reason=$reason generation=$_restoreGeneration',
    );
  }

  Future<List<Song>> _rehydrateSongsImpl(List<Song> songs) async {
    if (songs.isEmpty) return songs;

    final librarySongsById = <String, SongModel>{};
    final downloadedSongsById = <String, Song>{};

    try {
      final librarySongs = await _libraryRepository.getSongs();
      for (final song in librarySongs) {
        librarySongsById[song.id] = song;
      }
    } catch (e) {
      print('[PlaybackManager] Failed to load library songs for restore: $e');
    }

    try {
      await _downloadManager.initialize();
      for (final task in _downloadManager.queue) {
        if (task.status != DownloadStatus.completed) continue;
        downloadedSongsById[task.songId] = Song(
          id: task.songId,
          title: task.title,
          artist: task.artist,
          album: task.albumName,
          albumId: task.albumId,
          albumArtist: task.albumArtist,
          trackNumber: task.trackNumber,
          duration: Duration(seconds: task.duration),
          filePath: task.songId,
          fileSize: task.bytesDownloaded,
          modifiedTime: DateTime.now(),
        );
      }
    } catch (e) {
      print(
          '[PlaybackManager] Failed to load downloaded songs for restore: $e');
    }

    return songs
        .map(
          (song) => _rehydrateSong(
            song,
            librarySong: librarySongsById[song.id],
            downloadedSong: downloadedSongsById[song.id],
          ),
        )
        .toList();
  }

  Song _rehydrateSongImpl(
    Song song, {
    SongModel? librarySong,
    Song? downloadedSong,
  }) {
    var repaired = song;

    if (downloadedSong != null) {
      repaired = repaired.copyWith(
        title: downloadedSong.title,
        artist: downloadedSong.artist,
        album: downloadedSong.album ?? repaired.album,
        albumId: downloadedSong.albumId ?? repaired.albumId,
        albumArtist: downloadedSong.albumArtist ?? repaired.albumArtist,
        trackNumber: downloadedSong.trackNumber ?? repaired.trackNumber,
        duration: downloadedSong.duration > Duration.zero
            ? downloadedSong.duration
            : repaired.duration,
      );
    }

    if (librarySong != null) {
      repaired = repaired.copyWith(
        title: librarySong.title,
        artist: librarySong.artist,
        albumId: librarySong.albumId ?? repaired.albumId,
        trackNumber: librarySong.trackNumber ?? repaired.trackNumber,
        duration: librarySong.duration > 0
            ? Duration(seconds: librarySong.duration)
            : repaired.duration,
      );
    }

    return repaired;
  }

  void _updateCurrentSongDurationImpl(Duration duration) {
    final currentSong = _queue.currentSong;
    if (currentSong == null || currentSong.duration == duration) {
      return;
    }

    final updatedSongs = List<Song>.from(_queue.songs);
    updatedSongs[_queue.currentIndex] =
        currentSong.copyWith(duration: duration);
    _queue = PlaybackQueue(
      songs: updatedSongs,
      currentIndex: _queue.currentIndex,
    );
    unawaited(_saveState());
  }
}
