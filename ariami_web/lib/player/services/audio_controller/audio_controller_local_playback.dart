part of '../audio_controller.dart';

extension _AudioControllerLocalPlayback on AudioController {
  /// Retries a queue advance that failed while offline, once the connection
  /// is back. Returns false when there is nothing to resume (or the queue has
  /// since changed under the saved position).
  bool _maybeResumeInterruptedAdvance() {
    final resumePos = _resumeOrderPosOnReconnect;
    _resumeOrderPosOnReconnect = null;
    if (resumePos == null || _remote != null) return false;
    if (resumePos < 0 || resumePos >= _playOrder.length) return false;
    // The user started something else in the meantime; don't yank playback.
    if (_player.playing) return false;
    _orderPos = resumePos;
    unawaited(_loadCurrent(autoplay: true));
    return true;
  }

  Future<void> _loadCurrent({
    required bool autoplay,
    Duration? initialPosition,
  }) async {
    if (autoplay && _localPlaybackGuard.isSuspended) return;
    if (!_offlinePlayback && _client == null) return;

    // Any fresh load supersedes a pending offline-interrupted advance.
    final intendedOrderPos = _orderPos;
    _resumeOrderPosOnReconnect = null;

    // Offline, silently step over tracks that aren't downloaded so one
    // missing file doesn't halt the whole queue.
    if (_offlinePlayback && !_advanceToAvailableOffline()) {
      if (autoplay && _playOrder.isNotEmpty) {
        _resumeOrderPosOnReconnect = intendedOrderPos;
      }
      _errorMessage = _localCurrentTrack == null
          ? null
          : 'None of these songs are downloaded for offline playback.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    final track = currentTrack;
    if (track == null) return;
    if (identical(track, _resumeTrack)) {
      // Back to the track a play-now interrupted: pick up where it stopped.
      _resumeTrack = null;
      initialPosition ??= _resumeTrackPosition;
    }

    _localPlaybackGuard.disarmCompletion();
    final generation = ++_loadGeneration;
    _gaplessTailGeneration++;
    _gaplessTailPending = false;
    _autoplayBlocked = false;
    _isLoading = true;
    _errorMessage = null;
    _position = initialPosition ?? Duration.zero;
    _duration = track.durationSeconds > 0 ? track.duration : null;
    notifyListeners();

    final cast = _castService;
    if (cast != null && isCastActive) {
      if (_client == null) return;
      try {
        await cast.syncFromPlayback(
          track: track,
          position: initialPosition ?? Duration.zero,
          isPlaying: autoplay,
          apiClient: _client!,
          quality: quality,
          force: true,
        );
      } catch (e) {
        _errorMessage = 'Failed to stream track to Chromecast';
      } finally {
        if (generation == _loadGeneration) {
          _isLoading = false;
          notifyListeners();
        }
      }
      return;
    }

    try {
      try {
        await _loadTrackSource(
          track,
          generation: generation,
          initialPosition: initialPosition,
        );
      } catch (e) {
        if (generation != _loadGeneration) return;
        final canRetryM4a = kIsWeb &&
            !_offlinePlayback &&
            effectiveQuality == StreamQuality.high &&
            _shouldRetryWebM4a(e);
        if (!canRetryM4a) rethrow;
        await _loadTrackSource(
          track,
          generation: generation,
          initialPosition: initialPosition,
          formatOverride: 'm4a',
        );
      }
      if (generation != _loadGeneration) return;
      _unplayableSkipStreak = 0;
      // A play pressed mid-fetch starts now that the source is ready.
      final startPlaying = autoplay || _pendingAutoplay;
      _pendingAutoplay = false;
      if (startPlaying) {
        await _playLocalPlayer();
      }
    } catch (e) {
      if (generation != _loadGeneration) return;
      // A deferred play dies with the failed load.
      _pendingAutoplay = false;
      // The server no longer has this track (stale playlist/queue id): it can
      // never play, so skip past it instead of stalling the queue on it.
      if (e is PlayerApiException && e.code == 'SONG_NOT_FOUND') {
        await _skipUnplayableLocal(track, autoplay: autoplay);
        return;
      }
      // Covers the drop window before offline mode is flagged: the stream
      // token request fails on the dead network, and the reconnect retries it.
      if (autoplay) {
        _resumeOrderPosOnReconnect = _orderPos;
      }
      _errorMessage = 'Could not play "${track.title}": $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadTrackSource(
    Track track, {
    required int generation,
    Duration? initialPosition,
    String? formatOverride,
  }) async {
    if (_gapless.isEnabled) {
      final currentSource = await _sourceForTrack(
        track,
        formatOverride: formatOverride,
      );
      if (generation != _loadGeneration) return;

      _nativePlaylistOrderPositions = <int>[_orderPos];
      _settingNativePlaylist = true;
      try {
        await _resetWebPlaylist();
        await _player.setAudioSources(
          <AudioSource>[currentSource],
          initialIndex: 0,
          initialPosition: initialPosition ?? Duration.zero,
        );
        _activeNativeIndex = _player.currentIndex ?? 0;
      } finally {
        _settingNativePlaylist = false;
      }
      _observeLocalPlayerState(_player.playing, _player.processingState);
      if (generation == _loadGeneration) {
        _gaplessTailPending = _nextOrderPosition(_orderPos) != null;
      }
    } else {
      final source = await _sourceForTrack(
        track,
        formatOverride: formatOverride,
      );
      if (generation != _loadGeneration) return; // superseded
      _nativePlaylistOrderPositions = <int>[];
      _activeNativeIndex = null;
      await _resetWebPlaylist();
      await _player.setAudioSource(
        source,
        initialPosition: initialPosition ?? Duration.zero,
      );
    }
  }

  /// just_audio_web caches the playlist under just_audio's fixed playlist id,
  /// so reloading it replays the previous tracks. Stopping disposes the web
  /// player, and the next load starts from a fresh one.
  Future<void> _resetWebPlaylist() async {
    if (kIsWeb && _player.audioSource != null) await _player.stop();
  }

  bool _shouldRetryWebM4a(Object error) =>
      error is! PlayerApiException &&
      error is! _TrackUnavailableOffline &&
      error is! StateError;

  Future<void> _playLocalPlayer() async {
    _autoplayBlocked = false;
    try {
      await _player.play();
    } catch (e) {
      if (kIsWeb && _isAutoplayPolicyError(e)) {
        try {
          await _player.pause();
        } catch (_) {}
        _autoplayBlocked = true;
        _isPlaying = false;
        _isLoading = false;
        notifyListeners();
        return;
      }
      rethrow;
    }
  }

  bool _isAutoplayPolicyError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('notallowederror') ||
        text.contains('not allowed') ||
        text.contains('autoplay') ||
        text.contains('interact');
  }

  /// Skips past a track that can never play (deleted from the server
  /// library), notifying the UI which track was skipped. The streak cap stops
  /// the chain once every remaining queue entry has been tried, so a queue
  /// made entirely of stale ids halts instead of cycling forever under
  /// repeat-all.
  Future<void> _skipUnplayableLocal(
    Track track, {
    required bool autoplay,
  }) async {
    _unplayableTrackController.add(track);
    _unplayableSkipStreak++;

    final exhaustedQueue = _unplayableSkipStreak >= _playOrder.length;
    int? nextPos;
    if (!exhaustedQueue) {
      if (_orderPos < _playOrder.length - 1) {
        nextPos = _orderPos + 1;
      } else if (_repeat == PlayerRepeatMode.all && _playOrder.length > 1) {
        nextPos = 0;
      }
    }

    if (nextPos == null) {
      _unplayableSkipStreak = 0;
      await _player.pause();
      _isPlaying = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _orderPos = nextPos;
    await _loadCurrent(autoplay: autoplay);
  }

  Future<void> _togglePlayPauseLocal() async {
    if (_localCurrentTrack == null) return;
    if (_player.playing) {
      _invalidateLocalPlayback(suspend: true);
      await _player.pause();
      return;
    }
    // If the track finished, restart from the top.
    if (_player.processingState == ProcessingState.completed) {
      // Reloading obtains a fresh stream ticket. Seeking would reuse the
      // completed track's URL, which can expire during a long session.
      _invalidateLocalPlayback();
      await _loadCurrent(autoplay: true);
      return;
    }
    if (_awaitingSourceLoad) {
      // Still fetching (e.g. right after a relaunch): defer to the load.
      _deferPlayToLoad();
      return;
    }
    _invalidateLocalPlayback();
    unawaited(_playLocalPlayer());
  }

  Future<void> _nextLocal() async {
    if (_playOrder.isEmpty) return;
    // An explicit skip out of repeat-one drops to repeat-all and advances to
    // the next track rather than restarting the current one.
    if (_repeat == PlayerRepeatMode.one) {
      _repeat = PlayerRepeatMode.all;
    }
    if (_orderPos < _playOrder.length - 1) {
      _orderPos++;
    } else if (_repeat == PlayerRepeatMode.all) {
      _orderPos = 0;
    } else {
      return;
    }
    await _loadCurrent(autoplay: true);
  }

  Future<void> _previousLocal() async {
    // An explicit skip out of repeat-one drops to repeat-all and moves to the
    // previous track rather than restarting the current one.
    if (_repeat == PlayerRepeatMode.one) {
      _repeat = PlayerRepeatMode.all;
    } else if (_position.inSeconds > 3) {
      // Restart current track if we're more than a few seconds in.
      final cast = _castService;
      if (cast != null && isCastActive) {
        await cast.seek(Duration.zero);
      } else {
        await _player.seek(Duration.zero);
      }
      return;
    }
    if (_orderPos > 0) {
      _orderPos--;
    } else if (_repeat == PlayerRepeatMode.all && _playOrder.isNotEmpty) {
      _orderPos = _playOrder.length - 1;
    } else {
      final cast = _castService;
      if (cast != null && isCastActive) {
        await cast.seek(Duration.zero);
      } else {
        await _player.seek(Duration.zero);
      }
      return;
    }
    await _loadCurrent(autoplay: true);
  }

  Future<void> _onTrackCompleted() async {
    if (_localPlaybackGuard.isSuspended || _remote != null || isCastActive) {
      return;
    }
    if (_repeat == PlayerRepeatMode.one) {
      // A seek reuses the existing HTTP URL. Reload to obtain a fresh stream
      // ticket before the next repeat begins; local-file playback keeps using
      // its file source through the same loader.
      await _loadCurrent(autoplay: true);
      return;
    }
    if (_orderPos < _playOrder.length - 1) {
      _orderPos++;
      await _loadCurrent(autoplay: true);
    } else if (_repeat == PlayerRepeatMode.all && _playOrder.isNotEmpty) {
      _orderPos = 0;
      await _loadCurrent(autoplay: true);
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Removes the entry at an absolute position in the serialized play order —
  /// the index space a Connect controller sees in this device's published
  /// snapshots. The controller's snapshot may be stale, so the track id it
  /// saw at that position is verified first; on mismatch the first entry
  /// with that id is removed instead, and an unknown id is ignored. Only the
  /// The backing queue is compacted with the play order so persistence and a
  /// later shuffle cannot revive the removed occurrence.
  Future<void> _removeOrderPositionLocal(
    int position,
    String? expectedId,
  ) async {
    bool matches(int pos) {
      if (pos < 0 || pos >= _playOrder.length) return false;
      final queueIndex = _playOrder[pos];
      if (queueIndex < 0 || queueIndex >= _queue.length) return false;
      return expectedId == null || _queue[queueIndex].id == expectedId;
    }

    var target = position;
    if (!matches(target)) {
      if (expectedId == null) return;
      target = -1;
      for (var pos = 0; pos < _playOrder.length; pos++) {
        if (matches(pos)) {
          target = pos;
          break;
        }
      }
      if (target == -1) return;
    }

    if (target != _orderPos) {
      _playOrder.removeAt(target);
      if (target < _orderPos) _orderPos--;
      _compactQueueToPlayOrder();
      notifyListeners();
      unawaited(_refreshGaplessTail());
      return;
    }

    // Removing the playing track: the next one slides into its position
    // (matching queue-removal semantics on the other clients).
    final wasPlaying = _isPlaying;
    _playOrder.removeAt(target);
    _orderPos =
        _playOrder.isEmpty ? -1 : target.clamp(0, _playOrder.length - 1);
    _compactQueueToPlayOrder();
    if (_playOrder.isEmpty) {
      await _player.pause();
      _isPlaying = false;
      notifyListeners();
      return;
    }
    await _loadCurrent(autoplay: wasPlaying);
    notifyListeners();
  }

  void _clearUpcomingLocal() {
    if (_orderPos < 0 || _orderPos >= _playOrder.length) return;
    final currentQueueIndex = _playOrder[_orderPos];
    _playOrder = <int>[currentQueueIndex];
    _orderPos = 0;
    _compactQueueToPlayOrder();
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  /// Inserts [track] at an absolute position in the serialized play order —
  /// a Connect controller's undo of [_removeOrderPositionLocal]. Re-landing
  /// on the current position restores the track as the playing one.
  Future<void> _insertOrderPositionLocal(int position, Track track) async {
    if (track.id.isEmpty) return;
    _queue.add(track);
    final queueIndex = _queue.length - 1;

    if (_playOrder.isEmpty) {
      _playOrder.add(queueIndex);
      _orderPos = 0;
      await _loadCurrent(autoplay: false);
      notifyListeners();
      return;
    }

    final clamped = position.clamp(0, _playOrder.length);
    final restoreAsCurrent = clamped == _orderPos;
    final wasPlaying = _isPlaying;
    _playOrder.insert(clamped, queueIndex);
    if (restoreAsCurrent) {
      // Undoing the removal of the playing track: make it current again.
      _orderPos = clamped;
      await _loadCurrent(autoplay: wasPlaying);
    } else if (clamped < _orderPos) {
      _orderPos++;
    }
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  /// Jumps to an absolute position in the serialized play order — the index
  /// space a Connect controller sees in this device's published snapshots.
  Future<void> _jumpToOrderPositionLocal(int target) async {
    if (target < 0 || target >= _playOrder.length) return;
    if (target == _orderPos) return;
    if (_repeat == PlayerRepeatMode.one) {
      _repeat = PlayerRepeatMode.all;
    }
    _orderPos = target;
    await _loadCurrent(autoplay: true);
  }

  Future<void> _setVolumeLocal(double value) async {
    _volume = value.clamp(0.0, 1.0);
    final persistedVolume = _volume;
    unawaited(() async {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setDouble(
        AudioController._volumePreferenceKey,
        persistedVolume,
      );
    }());
    notifyListeners();
    await _player.setVolume(AudioController.volumeToGain(_volume));
  }

  void _toggleShuffleLocal() {
    _shuffle = !_shuffle;
    if (_playOrder.isEmpty) {
      notifyListeners();
      return;
    }
    final currentQueueIndex = _playOrder[_orderPos];
    if (_shuffle) {
      final rest = <int>[
        for (var i = 0; i < _queue.length; i++)
          if (i != currentQueueIndex) i,
      ]..shuffle(Random());
      _playOrder = <int>[currentQueueIndex, ...rest];
    } else {
      _playOrder = List<int>.generate(_queue.length, (i) => i);
    }
    _orderPos = _playOrder.indexOf(currentQueueIndex);
    final nativeIndex = _activeNativeIndex;
    if (nativeIndex != null &&
        nativeIndex >= 0 &&
        nativeIndex < _nativePlaylistOrderPositions.length) {
      _nativePlaylistOrderPositions[nativeIndex] = _orderPos;
    }
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  void _cycleRepeatLocal() {
    switch (_repeat) {
      case PlayerRepeatMode.off:
        _repeat = PlayerRepeatMode.all;
        break;
      case PlayerRepeatMode.all:
        _repeat = PlayerRepeatMode.one;
        break;
      case PlayerRepeatMode.one:
        _repeat = PlayerRepeatMode.off;
        break;
    }
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }
}
