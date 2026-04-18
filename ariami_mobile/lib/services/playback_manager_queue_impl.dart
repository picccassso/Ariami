part of 'playback_manager.dart';

extension _PlaybackManagerQueueImpl on PlaybackManager {
  Future<void> _playSongImpl(Song song) async {
    print('[PlaybackManager] ========== playSong() called ==========');
    print('[PlaybackManager] Song: ${song.title} by ${song.artist}');
    print('[PlaybackManager] FilePath: ${song.filePath}');
    print('[PlaybackManager] Duration: ${song.duration}');

    // Clear restored position - this is a NEW song, start from beginning
    _invalidatePendingRestore('playSong');
    _restoredPosition = null;
    _pendingUiPosition = null;

    // Reset shuffle state - new queue means fresh shuffle context
    _isShuffleEnabled = false;
    _shuffleService.reset();

    try {
      // Create new queue with just this song
      print('[PlaybackManager] Creating new queue...');
      _queue = PlaybackQueue();
      _queue.addSong(song);
      print('[PlaybackManager] Queue created with ${_queue.length} song(s)');
      print(
          '[PlaybackManager] Current song in queue: ${_queue.currentSong?.title}');

      print('[PlaybackManager] Calling _playCurrentSong()...');
      await _playCurrentSong();
      print(
          '[PlaybackManager] _playCurrentSong() completed, notifying listeners...');
      _notifyStateChanged();
      await _saveState(); // Save state after playing new song
      print('[PlaybackManager] ========== playSong() completed ==========');
    } catch (e, stackTrace) {
      print('[PlaybackManager] ========== ERROR in playSong() ==========');
      print('[PlaybackManager] Error: $e');
      print('[PlaybackManager] Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _playSongsImpl(List<Song> songs, {int startIndex = 0}) async {
    try {
      if (songs.isEmpty) return;

      // Clear restored position - these are NEW songs, start from beginning
      _invalidatePendingRestore('playSongs');
      _restoredPosition = null;
      _pendingUiPosition = null;

      // Reset shuffle state - new queue means fresh shuffle context
      _isShuffleEnabled = false;
      _shuffleService.reset();

      // Create new queue with all songs
      _queue = PlaybackQueue();
      for (final song in songs) {
        _queue.addSong(song);
      }

      // Jump to start index
      if (startIndex > 0 && startIndex < songs.length) {
        _queue.jumpToIndex(startIndex);
      }

      await _playCurrentSong();
      _notifyStateChanged();
      await _saveState(); // Save state after playing songs
    } catch (e) {
      print('[PlaybackManager] Error playing songs: $e');
      rethrow;
    }
  }

  Future<void> _playShuffledImpl(List<Song> songs) async {
    try {
      if (songs.isEmpty) return;

      // Clear restored position - these are NEW songs, start from beginning
      _invalidatePendingRestore('playShuffled');
      _restoredPosition = null;
      _pendingUiPosition = null;

      // Shuffle the list using shuffle service
      final shuffled = _shuffleService.enableShuffle(songs, null);

      // Create queue with shuffled songs
      _queue = PlaybackQueue();
      for (final song in shuffled) {
        _queue.addSong(song);
      }

      _isShuffleEnabled = true;
      await _playCurrentSong();
      _notifyStateChanged();
      await _saveState(); // Save state after playing shuffled
    } catch (e) {
      print('[PlaybackManager] Error playing shuffled: $e');
      rethrow;
    }
  }

  void _addToQueueImpl(Song song) {
    _queue.addSong(song);
    _notifyStateChanged();
  }

  void _addAllToQueueImpl(List<Song> songs) {
    for (final song in songs) {
      _queue.addSong(song);
    }
    _notifyStateChanged();
  }

  void _playNextImpl(Song song) {
    _queue.insertSong(_queue.currentIndex + 1, song);
    _notifyStateChanged();
  }

  Future<void> _togglePlayPauseImpl() async {
    try {
      if (_castService.isConnected) {
        if (isPlaying) {
          await _statsService.onSongStopped();
          await _castService.pause();
        } else {
          if (currentSong == null) return;
          _statsService.onSongStarted(currentSong!);
          await _castService.play();
        }
        _notifyStateChanged();
        return;
      }

      if (isPlaying) {
        // Pausing - stop stats tracking
        await _statsService.onSongStopped();
        await _audioPlayer.pause();
        await _saveState(); // Save state when pausing
      } else {
        if (currentSong == null) return;

        // If no song is loaded yet OR we have a restored position to seek to, load/reload the song
        if (duration == null || _restoredPosition != null) {
          await _playCurrentSong();
        } else {
          // Resuming - restart stats tracking
          _statsService.onSongStarted(currentSong!);
          await _audioPlayer.resume();
        }
      }
      _notifyStateChanged();
    } catch (e) {
      print('[PlaybackManager] Error in togglePlayPause: $e');
    }
  }

  Future<void> _skipNextImpl() async {
    try {
      if (!_queue.hasNext) {
        // Check repeat mode
        if (_repeatMode == RepeatMode.all && _queue.songs.isNotEmpty) {
          // Find first available song from beginning when wrapping
          final nextIndex = await _findNextAvailableSongIndexFrom(0);
          if (nextIndex != null) {
            await _statsService.onSongStopped();
            _queue.jumpToIndex(nextIndex);
            _restoredPosition = null;
            _pendingUiPosition = null;

            _notifyStateChanged();
            await Future.delayed(const Duration(milliseconds: 700));
            if (_queue.currentIndex != nextIndex) return;

            await _playCurrentSong();
            _notifyStateChanged();
            await _saveState();
          }
        } else if (_repeatMode == RepeatMode.one) {
          // Replay current song
          await seek(Duration.zero);
          _statsService.onSongStarted(currentSong!);
          if (_castService.isConnected) {
            await _castService.play();
          } else {
            await _audioPlayer.resume();
          }
        }
        return;
      }

      // Find next available song
      final nextIndex = await _findNextAvailableSongIndex();
      if (nextIndex == null) {
        print('[PlaybackManager] No available next song found');
        return;
      }

      // Stop tracking current song
      await _statsService.onSongStopped();

      _queue.jumpToIndex(nextIndex);
      // Clear restored position so new song starts from beginning
      _restoredPosition = null;
      _pendingUiPosition = null;

      _notifyStateChanged();
      await Future.delayed(const Duration(milliseconds: 700));
      if (_queue.currentIndex != nextIndex) return;

      await _playCurrentSong();
      _notifyStateChanged();
      await _saveState(); // Save state after skipping to next song
    } catch (e) {
      print('[PlaybackManager] Error skipping next: $e');
    }
  }

  Future<void> _skipPreviousImpl() async {
    try {
      // If more than 3 seconds into song, restart it
      if (position.inSeconds > 3) {
        await seek(Duration.zero);
        return;
      }

      if (!_queue.hasPrevious) return;

      // Find previous available song when offline
      final previousIndex = await _findPreviousAvailableSongIndex();
      if (previousIndex == null) {
        print('[PlaybackManager] No available previous song found');
        return;
      }

      // Stop tracking current song
      await _statsService.onSongStopped();

      _queue.jumpToIndex(previousIndex);
      // Clear restored position so new song starts from beginning
      _restoredPosition = null;
      _pendingUiPosition = null;

      _notifyStateChanged();
      await Future.delayed(const Duration(milliseconds: 700));
      if (_queue.currentIndex != previousIndex) return;

      await _playCurrentSong();
      _notifyStateChanged();
      await _saveState(); // Save state after skipping to previous song
    } catch (e) {
      print('[PlaybackManager] Error skipping previous: $e');
    }
  }

  Future<void> _skipToQueueItemImpl(int index) async {
    try {
      if (index < 0 || index >= _queue.length) return;
      if (index == _queue.currentIndex) return;

      // Stop tracking current song
      await _statsService.onSongStopped();

      _queue.jumpToIndex(index);
      // Clear restored position so new song starts from beginning
      _restoredPosition = null;
      _pendingUiPosition = null;
      await _playCurrentSong();
      _notifyStateChanged();
      await _saveState(); // Save state after skipping to specific item
    } catch (e) {
      print('[PlaybackManager] Error skipping to queue item: $e');
    }
  }

  Future<void> _seekImpl(Duration position) async {
    try {
      // User is manually seeking - update restored position so pressing play
      // will start from the scrubbed position (not the old saved position)
      _restoredPosition = position;
      _pendingUiPosition = position;
      _notifyStateChanged(); // Notify immediately so UI updates before async seek

      if (_castService.isConnected) {
        await _castService.seek(position, playAfterSeek: isPlaying);
        // Clear restored position after successful cast seek
        _restoredPosition = null;
        _pendingUiPosition = null;
        _notifyStateChanged();
        return;
      }

      await _audioPlayer.seek(position);
      // If the song is loaded and seek succeeded, clear the restored position
      if (_audioPlayer.duration != null) {
        _restoredPosition = null;
        _pendingUiPosition = null;
      }
      _notifyStateChanged();
    } catch (e) {
      print('[PlaybackManager] Error seeking: $e');
    }
  }

  void _toggleShuffleImpl() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_isShuffleEnabled && _queue.isNotEmpty) {
      // Shuffle remaining songs in queue (keeping current song at position 0)
      final shuffled =
          _shuffleService.enableShuffle(_queue.songs, _queue.currentSong);

      // Rebuild queue with shuffled songs, current song is at index 0
      _queue.setQueue(shuffled, currentIndex: 0);
    } else if (!_isShuffleEnabled && _shuffleService.isShuffled) {
      // Restore original order
      final original = _shuffleService.disableShuffle(_queue.currentSong);

      // Find where the current song is in the original queue
      final currentSong = _queue.currentSong;
      int newIndex = 0;
      if (currentSong != null) {
        final foundIndex = original.indexOf(currentSong);
        if (foundIndex != -1) {
          newIndex = foundIndex;
        }
      }

      // Rebuild queue with original order, maintaining current song position
      _queue.setQueue(original, currentIndex: newIndex);
    }

    _notifyStateChanged();
    await _saveState(); // Save state after shuffle toggle
  }

  void _reorderQueueFromDisplayOrderImpl(
    int oldDisplayIndex,
    int newDisplayIndex,
  ) {
    final songs = _queue.songs;
    if (songs.isEmpty) return;

    final len = songs.length;
    final c = _queue.currentIndex.clamp(0, len - 1);
    final displayed = <Song>[
      ...songs.sublist(c),
      ...songs.sublist(0, c),
    ];

    if (oldDisplayIndex < 0 ||
        oldDisplayIndex >= len ||
        newDisplayIndex < 0 ||
        newDisplayIndex >= len) {
      return;
    }

    // Now playing is pinned at the top; drag handle is disabled for row 0.
    if (oldDisplayIndex == 0) return;
    if (newDisplayIndex == 0 && oldDisplayIndex != 0) return;

    final moved = displayed.removeAt(oldDisplayIndex);
    displayed.insert(newDisplayIndex, moved);

    final current = _queue.currentSong;
    if (current != null && displayed.first.id != current.id) {
      return;
    }

    _queue.setQueue(displayed, currentIndex: 0);
    _notifyStateChanged();
    unawaited(_saveState());
  }

  void _toggleRepeatImpl() async {
    _repeatMode = _repeatMode.next;
    _notifyStateChanged();
    await _saveState(); // Save state after repeat toggle
  }

  Future<void> _clearQueueImpl() async {
    // Stop tracking current song
    await _statsService.onSongStopped();
    await _audioPlayer.stop();
    _queue.clear();
    await _stateManager.clearCompletePlaybackState(
      userId: _connectionService.userId,
    ); // Clear saved state
    _notifyStateChanged();
  }

  Future<int?> _findNextAvailableSongIndexImpl() async {
    final songs = _queue.songs;
    final currentIndex = _queue.currentIndex;

    // If online, just return the next index
    if (!_offlineService.isOffline) {
      return currentIndex < songs.length - 1 ? currentIndex + 1 : null;
    }

    // Search forward from current position
    for (int i = currentIndex + 1; i < songs.length; i++) {
      final isAvailable =
          await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    // If repeat all is enabled, wrap around and search from beginning
    if (_repeatMode == RepeatMode.all) {
      for (int i = 0; i < currentIndex; i++) {
        final isAvailable =
            await _offlineService.isSongAvailableOffline(songs[i].id);
        if (isAvailable) {
          return i;
        }
      }
    }

    return null; // No available songs found
  }

  Future<int?> _findNextAvailableSongIndexFromImpl(int startIndex) async {
    final songs = _queue.songs;

    // If online, just return the start index
    if (!_offlineService.isOffline) {
      return startIndex < songs.length ? startIndex : null;
    }

    // Search from start index
    for (int i = startIndex; i < songs.length; i++) {
      final isAvailable =
          await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    return null;
  }

  Future<int?> _findPreviousAvailableSongIndexImpl() async {
    final songs = _queue.songs;
    final currentIndex = _queue.currentIndex;

    // If online, just return the previous index
    if (!_offlineService.isOffline) {
      return currentIndex > 0 ? currentIndex - 1 : null;
    }

    // Search backward from current position
    for (int i = currentIndex - 1; i >= 0; i--) {
      final isAvailable =
          await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    // If repeat all is enabled, wrap around and search from end
    if (_repeatMode == RepeatMode.all) {
      for (int i = songs.length - 1; i > currentIndex; i--) {
        final isAvailable =
            await _offlineService.isSongAvailableOffline(songs[i].id);
        if (isAvailable) {
          return i;
        }
      }
    }

    return null; // No available songs found
  }

  Future<void> _onSongCompletedImpl() async {
    print('[PlaybackManager] Song completed');

    if (_repeatMode == RepeatMode.one) {
      // Replay the same song - finalize current first
      await _statsService.onSongStopped();
      await _playCurrentSong();
    } else if (_queue.hasNext) {
      // Move to next song - skipNext() will handle finalization
      // Don't call onSongStopped() here to avoid double-call
      await skipNext();
    } else if (_repeatMode == RepeatMode.all && _queue.songs.isNotEmpty) {
      // Restart from beginning - finalize current first
      await _statsService.onSongStopped();
      _queue.jumpToIndex(0);
      await _playCurrentSong();
    } else {
      // Queue finished, stop - finalize current first
      await _statsService.onSongStopped();
      _audioPlayer.stop();
      _notifyStateChanged();
    }
  }
}
