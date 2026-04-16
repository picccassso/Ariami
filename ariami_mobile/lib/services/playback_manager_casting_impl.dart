part of 'playback_manager.dart';

extension _PlaybackManagerCastingImpl on PlaybackManager {
  Future<void> _startCastingToDeviceImpl(GoogleCastDevice device) async {
    if (_isCastTransitionInProgress) {
      print('[PlaybackManager] Cast handoff already in progress');
      return;
    }
    if (_castService.isConnected || _castService.isConnecting) {
      print('[PlaybackManager] Cast handoff ignored: session already active');
      return;
    }

    _isCastTransitionInProgress = true;
    _notifyStateChanged();

    var snapshot = _PlaybackHandoffState(
      song: currentSong,
      position: _pendingUiPosition ?? _audioPlayer.position,
      wasPlaying: _audioPlayer.isPlaying,
    );
    final initialSongId = snapshot.song?.id;
    final shouldFreezeLocal = snapshot.wasPlaying || _audioPlayer.isLoading;

    try {
      if (shouldFreezeLocal) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 120));

        final frozenSong = currentSong;
        if (initialSongId != null && frozenSong?.id != initialSongId) {
          throw StateError(
            'Playback changed during Chromecast handoff; aborting cast.',
          );
        }

        final frozenPosition = _pendingUiPosition ?? _audioPlayer.position;
        snapshot = _PlaybackHandoffState(
          song: frozenSong ?? snapshot.song,
          position: frozenPosition > snapshot.position
              ? frozenPosition
              : snapshot.position,
          wasPlaying: snapshot.wasPlaying,
        );
        _pendingUiPosition = snapshot.position;
        print(
          '[PlaybackManager] Frozen local playback for cast: '
          'song=${snapshot.song?.id}/${snapshot.song?.title} '
          'position=${snapshot.position.inMilliseconds}ms '
          'wasPlaying=${snapshot.wasPlaying}',
        );
        _notifyStateChanged();
      }

      await _castService.connectToDevice(device);

      if (snapshot.song != null) {
        if (currentSong?.id != snapshot.song?.id) {
          throw StateError(
            'Queue song changed during Chromecast handoff; aborting cast.',
          );
        }
        final casted = await _castService.syncFromPlayback(
          song: snapshot.song,
          position: snapshot.position,
          isPlaying: snapshot.wasPlaying,
          force: true,
        );
        if (!casted) {
          throw StateError(
            'Chromecast session connected but the media handoff failed.',
          );
        }
      }

      _notifyStateChanged();
    } catch (e) {
      await _restoreLocalPlaybackSnapshot(snapshot);
      rethrow;
    } finally {
      _isCastTransitionInProgress = false;
      _notifyStateChanged();
    }
  }

  Future<void> _stopCastingAndResumeLocalImpl() async {
    if (!_castService.isConnected) {
      return;
    }

    _castService.logDebugSnapshot('playback-manager-pre-disconnect');
    final snapshot = _PlaybackHandoffState(
      song: currentSong,
      position: _castService.remotePosition,
      wasPlaying: _castService.isRemotePlaying,
    );
    print(
      '[PlaybackManager] Disconnect snapshot: '
      'song=${snapshot.song?.id}/${snapshot.song?.title} '
      'rawRemote=${_castService.rawRemotePosition.inMilliseconds}ms '
      'capturedRemote=${snapshot.position.inMilliseconds}ms '
      'wasPlaying=${snapshot.wasPlaying}',
    );

    if (snapshot.song == null) {
      await _castService.beginLocalPlaybackHandoff(
        capturedPosition: snapshot.position,
        wasPlaying: snapshot.wasPlaying,
      );
      _castService.disconnectInBackground();
      _notifyStateChanged();
      return;
    }

    await _castService.beginLocalPlaybackHandoff(
      capturedPosition: snapshot.position,
      wasPlaying: snapshot.wasPlaying,
    );
    print(
      '[PlaybackManager] Local handoff prepared, continuing with local restore',
    );
    await _restoreLocalPlaybackSnapshot(snapshot);
    _castService.disconnectInBackground();
    print('[PlaybackManager] Background Chromecast disconnect requested');
    await _saveState();
  }

  Future<void> _restoreLocalPlaybackSnapshotImpl(
    _PlaybackHandoffState snapshot,
  ) async {
    if (snapshot.song == null) {
      return;
    }

    final loadedLocalSong = _audioPlayer.currentSong;
    final loadedSongMatches = loadedLocalSong?.id == snapshot.song?.id;

    print(
      '[PlaybackManager] Restoring local snapshot: '
      'song=${snapshot.song?.id}/${snapshot.song?.title} '
      'loadedLocalSong=${loadedLocalSong?.id}/${loadedLocalSong?.title} '
      'loadedSongMatches=$loadedSongMatches '
      'target=${snapshot.position.inMilliseconds}ms '
      'wasPlaying=${snapshot.wasPlaying} '
      'localBefore=${_audioPlayer.position.inMilliseconds}ms',
    );
    _pendingUiPosition = snapshot.position;

    if (!loadedSongMatches) {
      print(
        '[PlaybackManager] Loaded local song mismatch during restore, '
        'reloading snapshot song instead of resuming in-place',
      );
      await _reloadLocalPlaybackFromSnapshot(snapshot);
      _notifyStateChanged();
      return;
    }

    try {
      await _audioPlayer.seek(snapshot.position);
      print(
        '[PlaybackManager] Local seek completed: '
        'afterSeek=${_audioPlayer.position.inMilliseconds}ms',
      );
      if (snapshot.wasPlaying) {
        await _audioPlayer.resume();
        print(
          '[PlaybackManager] Local resume requested: '
          'afterResume=${_audioPlayer.position.inMilliseconds}ms '
          'isPlaying=${_audioPlayer.isPlaying}',
        );
        final resumeRecovered =
            await _verifyLocalResumeProgress(snapshot.position);
        if (!resumeRecovered) {
          print(
            '[PlaybackManager] Local resume stalled, reloading current song at '
            '${snapshot.position.inMilliseconds}ms',
          );
          await _reloadLocalPlaybackFromSnapshot(snapshot);
        }
      }
    } catch (_) {
      _restoredPosition = snapshot.position;
      print(
        '[PlaybackManager] Local restore fallback triggered: '
        'restoredPosition=${_restoredPosition?.inMilliseconds}ms',
      );
      await _playCurrentSong(
        autoPlay: snapshot.wasPlaying,
        restartStatsTracking: false,
      );
      print(
        '[PlaybackManager] Local restore fallback completed: '
        'localAfterFallback=${_audioPlayer.position.inMilliseconds}ms '
        'isPlaying=${_audioPlayer.isPlaying}',
      );
    }

    _notifyStateChanged();
  }

  Future<bool> _verifyLocalResumeProgressImpl(Duration expectedPosition) async {
    await Future.delayed(const Duration(milliseconds: 900));

    final currentPosition = _audioPlayer.position;
    final minimumAdvancedPosition =
        expectedPosition + const Duration(milliseconds: 250);
    final hasAdvanced = currentPosition >= minimumAdvancedPosition;

    print(
      '[PlaybackManager] Local resume verification: '
      'current=${currentPosition.inMilliseconds}ms '
      'expectedAtLeast=${minimumAdvancedPosition.inMilliseconds}ms '
      'isPlaying=${_audioPlayer.isPlaying} '
      'hasAdvanced=$hasAdvanced',
    );

    return hasAdvanced;
  }

  Future<void> _reloadLocalPlaybackFromSnapshotImpl(
    _PlaybackHandoffState snapshot,
  ) async {
    _restoredPosition = snapshot.position;
    _pendingUiPosition = snapshot.position;
    await _playCurrentSong(
      autoPlay: snapshot.wasPlaying,
      restartStatsTracking: false,
    );
    print(
      '[PlaybackManager] Local reload after stalled resume completed: '
      'localAfterReload=${_audioPlayer.position.inMilliseconds}ms '
      'isPlaying=${_audioPlayer.isPlaying}',
    );
  }
}

class _PlaybackHandoffState {
  final Song? song;
  final Duration position;
  final bool wasPlaying;

  const _PlaybackHandoffState({
    required this.song,
    required this.position,
    required this.wasPlaying,
  });
}
