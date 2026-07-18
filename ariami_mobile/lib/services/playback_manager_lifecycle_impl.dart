part of 'playback_manager.dart';

extension _PlaybackManagerLifecycleImpl on PlaybackManager {
  /// Initialize the playback manager and set up listeners
  void _initializeImpl() {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;
    _queue = PlaybackQueue();
    _oneShotQueuedSongs.clear();
    _isShuffleEnabled = false;
    _repeatMode = RepeatMode.none;
    _shuffleService.reset();
    _restoredPosition = null;
    _pendingUiPosition = null;
    _gaplessPlayback.initialize();
    _gaplessPlayback.addListener(_onGaplessPreferenceChanged);

    _castService.initialize();
    _castService.addListener(_onCastStateChanged);

    _networkTypeSubscription = _qualityService.networkTypeStream.listen((_) {
      if (!_qualityService.allowsSpeculativeMediaDownloads) {
        _cacheManager.cancelPendingSongCaches();
      } else if (_deferredGaplessSongId == _queue.currentSong?.id) {
        unawaited(_refreshGaplessQueue());
      }
    });

    _bufferedPositionSubscription =
        _audioPlayer.bufferedPositionStream.listen((bufferedPosition) {
      if (_deferredGaplessSongId != _queue.currentSong?.id) return;
      if (!hasSpeculativeGaplessHeadroom(
        position: _audioPlayer.position,
        bufferedPosition: bufferedPosition,
        duration: _audioPlayer.duration,
      )) {
        return;
      }
      _deferredGaplessSongId = null;
      unawaited(_refreshGaplessQueue());
    });

    // Listen to position updates
    _positionSubscription = _audioPlayer.positionStream.listen((pos) {
      if (_pendingUiPosition != null && pos >= _pendingUiPosition!) {
        _pendingUiPosition = null;
      }
      _statsService.updatePosition(pos);
      _notifyStateChanged();
    });

    // Listen to duration updates
    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null &&
          duration > Duration.zero &&
          _audioPlayer.currentSong?.id == _queue.currentSong?.id) {
        _updateCurrentSongDuration(duration);
      }
      _notifyStateChanged();
    });

    // Listen to player state changes
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (!_castService.isConnected) {
        _statsService.setPlaybackActive(
          state.playing && state.processingState == ProcessingState.ready,
        );
      }
      _notifyStateChanged();

      // Auto-advance when song completes
      if (state.processingState == ProcessingState.completed) {
        unawaited(() async {
          try {
            await _onSongCompleted();
          } catch (e) {
            print('[PlaybackManager] Error in _onSongCompleted: $e');
          }
        }());
      }
    });

    // Listen to skip next button from notification
    _skipNextSubscription = audioHandler?.onSkipNext.listen((_) {
      print('[PlaybackManager] Skip Next pressed from notification');
      skipNext();
    });

    // Listen to skip previous button from notification
    _skipPreviousSubscription = audioHandler?.onSkipPrevious.listen((_) {
      print('[PlaybackManager] Skip Previous pressed from notification');
      skipPrevious();
    });

    _seekSubscription = _audioPlayer.seekStream.listen((_) {
      _statsService.markPositionDiscontinuity();
    });

    _gaplessTransitionSubscription =
        _audioPlayer.gaplessTransitionStream.listen((transition) {
      unawaited(_handleGaplessTransition(transition));
    });

    // Mute when silent, unmute when unsilenced: pause local playback when the
    // system media volume reaches zero and resume it when raised back up.
    // Pass the playback category so the iOS listener keeps the audio session
    // compatible with audio_service's background playback session.
    _volumeSubscription = FlutterVolumeController.addListener(
      _onSystemVolumeChanged,
      category: AudioSessionCategory.playback,
    );

    // Set up periodic save timer for position updates
    _saveTimer = Timer.periodic(
      PlaybackManager._saveDebounceDuration,
      (_) async {
        if (currentSong != null && isPlaying) {
          await _saveState();
        }
      },
    );

    // Restore saved state
    _restoreState();
  }

  /// React to system media-volume changes for the "mute when silent" feature.
  ///
  /// When the volume drops to zero we pause local playback (so the track does
  /// not keep advancing inaudibly) and remember that we did so. When the volume
  /// is raised again we resume — but only if the pause was ours, never after a
  /// manual pause. Casting has its own volume control, so we leave it alone.
  void _onSystemVolumeChanged(double volume) {
    if (_castService.isConnected) {
      return;
    }

    // outputVolume can report tiny non-zero values; treat near-zero as silent.
    final isSilent = volume <= 0.0001;

    if (isSilent) {
      if (_audioPlayer.isPlaying && !_pausedBySilence) {
        _pausedBySilence = true;
        unawaited(() async {
          try {
            await _statsService.onSongStopped();
            await _audioPlayer.pause();
            await _saveState();
            _notifyStateChanged();
          } catch (e) {
            print('[PlaybackManager] Error pausing for silence: $e');
          }
        }());
      }
    } else if (_pausedBySilence) {
      _pausedBySilence = false;
      if (currentSong != null && !_audioPlayer.isPlaying) {
        unawaited(() async {
          try {
            _statsService.onSongStarted(currentSong!, isResume: true);
            await _audioPlayer.resume();
            _notifyStateChanged();
          } catch (e) {
            print('[PlaybackManager] Error resuming after silence: $e');
          }
        }());
      }
    }
  }

  void _onCastStateChanged() {
    final status = _castService.mediaStatus;
    final nextState = status?.playerState;
    final idleReason = status?.idleReason;

    final wasAdvancing =
        _lastObservedCastPlayerState == CastMediaPlayerState.playing ||
            _lastObservedCastPlayerState == CastMediaPlayerState.buffering ||
            _lastObservedCastPlayerState == CastMediaPlayerState.loading;
    final completedRemotely = wasAdvancing &&
        nextState == CastMediaPlayerState.idle &&
        idleReason == GoogleCastMediaIdleReason.finished;

    _lastObservedCastPlayerState = nextState;

    if (!_castService.isConnected) {
      audioHandler?.exitCastMode();
      _lastObservedCastPlayerState = null;
      _castStatsForwardTimer?.cancel();
      _castStatsForwardTimer = null;
      _statsService.setPlaybackActive(false);
      _notifyStateChanged();
      return;
    }

    _statsService.setPlaybackActive(
      _castService.isRemotePlaying && !_castService.isRemoteBuffering,
    );

    audioHandler?.updateCastPlaybackState(
      position: _castService.remotePosition,
      isPlaying: _castService.isRemotePlaying,
      duration: _castService.remoteDuration ?? currentSong?.duration,
      isBuffering: _castService.isRemoteBuffering,
    );

    // Forward cast position updates to stats service
    _castStatsForwardTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_castService.isConnected) {
          _statsService.updatePosition(_castService.remotePosition);
        }
      },
    );

    if (completedRemotely && !_isHandlingCastCompletion) {
      _isHandlingCastCompletion = true;
      unawaited(() async {
        try {
          await _onSongCompleted();
        } catch (e) {
          print('[PlaybackManager] Error in remote _onSongCompleted: $e');
        } finally {
          _isHandlingCastCompletion = false;
        }
      }());
    }

    _notifyStateChanged();
  }
}
