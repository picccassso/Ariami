part of '../audio_controller.dart';

extension _AudioControllerPlayerEvents on AudioController {
  void _wireStreams() {
    _player.playerStateStream.listen(
      (state) {
        _isPlaying = state.playing;
        if (state.playing) _autoplayBlocked = false;
        _isLoading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        _observeLocalPlayerState(state.playing, state.processingState);
        notifyListeners();
      },
      onError: (_) {},
    );
    _player.positionStream.listen((p) {
      if (p == _position) return;
      // A seek or track change shows at once; steady playback is coalesced.
      final jumped = (p - _position).abs() > const Duration(seconds: 1);
      _position = p;
      _maybeAppendGaplessTail();
      _notifyProgress(now: jumped);
    });
    _player.bufferedPositionStream.listen((p) {
      if (p == _bufferedPosition) return;
      _bufferedPosition = p;
      // Buffered progress also fires while paused, so a paused restore still
      // gets its deferred gapless tail once the buffer allows it.
      _maybeAppendGaplessTail();
      _progress.tick();
    });
    _player.durationStream.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.currentIndexStream.listen(_onNativeIndexChanged);
  }

  void _observeLocalPlayerState(bool playing, ProcessingState state) {
    final completion = _localPlaybackGuard.observePlayerState(
      playing: playing &&
          _remote == null &&
          !isCastActive &&
          !_settingNativePlaylist,
      ready: state == ProcessingState.ready,
      completed: state == ProcessingState.completed,
    );
    if (completion != null) {
      unawaited(_onTrackCompleted().whenComplete(
        () => _localPlaybackGuard.finishCompletion(completion),
      ));
    }
  }

  void _onNativeIndexChanged(int? nativeIndex) {
    if (_localPlaybackGuard.isSuspended ||
        _remote != null ||
        _settingNativePlaylist ||
        !_gapless.isEnabled ||
        nativeIndex == null ||
        nativeIndex < 0 ||
        nativeIndex >= _nativePlaylistOrderPositions.length) {
      return;
    }

    final previousNativeIndex = _activeNativeIndex;
    _activeNativeIndex = nativeIndex;
    if (previousNativeIndex == null || previousNativeIndex == nativeIndex) {
      return;
    }

    final nextOrderPosition = _nativePlaylistOrderPositions[nativeIndex];
    if (nextOrderPosition == _orderPos ||
        nextOrderPosition < 0 ||
        nextOrderPosition >= _playOrder.length) {
      return;
    }

    // The native engine has already crossed the sample boundary. Update the
    // public queue metadata immediately, then prepare one fresh URL ahead.
    _orderPos = nextOrderPosition;
    _position = Duration.zero;
    final track = _localCurrentTrack;
    _duration =
        track != null && track.durationSeconds > 0 ? track.duration : null;
    _errorMessage = null;
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }
}
