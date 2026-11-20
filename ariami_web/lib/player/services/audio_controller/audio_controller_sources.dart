part of '../audio_controller.dart';

extension _AudioControllerSources on AudioController {
  void _buildPlayOrder({required int startQueueIndex}) {
    final indices = List<int>.generate(_queue.length, (i) => i);
    if (_shuffle) {
      indices.removeAt(startQueueIndex);
      indices.shuffle(Random());
      _playOrder = <int>[startQueueIndex, ...indices];
    } else {
      // Rotate so startQueueIndex is first while preserving linear order after.
      _playOrder = <int>[
        for (var i = startQueueIndex; i < _queue.length; i++) i,
        for (var i = 0; i < startQueueIndex; i++) i,
      ];
    }
  }

  int? _nextOrderPosition(int from) {
    if (_repeat == PlayerRepeatMode.one || _playOrder.length < 2) return null;
    if (from >= 0 && from < _playOrder.length - 1) return from + 1;
    return _repeat == PlayerRepeatMode.all ? 0 : null;
  }

  Future<AudioSource> _sourceForOrderPosition(int orderPosition) async {
    if (orderPosition < 0 || orderPosition >= _playOrder.length) {
      throw StateError('Cannot resolve an audio source without a queue');
    }
    return _sourceForTrack(_queue[_playOrder[orderPosition]]);
  }

  Future<AudioSource> _sourceForTrack(
    Track track, {
    String? formatOverride,
  }) async {
    // The gapless tail resolves the *next* track's source through here too;
    // only the current track's resolution is recorded for the debug overlay.
    final record = track.id == _localCurrentTrack?.id;
    if (_offlinePlayback) {
      final path = localFileResolver?.call(track.id);
      if (path == null) throw _TrackUnavailableOffline(track);
      if (record) _recordFileSource(PlaybackSourceKind.offlineFile, path);
      return AudioSource.file(path, tag: track.id);
    }
    if (_qualityPolicy.isLocalPlayback) {
      final path = serverFileResolver?.call(track.id);
      if (path != null &&
          (await _host?.localFileExists?.call(path) ?? false)) {
        if (record) _recordFileSource(PlaybackSourceKind.serverFile, path);
        return AudioSource.file(path, tag: track.id);
      }
    }
    if (_preferDownloadedWhenOnline) {
      final path = downloadedFileResolver?.call(track.id, effectiveQuality);
      if (path != null) {
        if (record) {
          _recordFileSource(PlaybackSourceKind.downloadedFile, path);
        }
        return AudioSource.file(path, tag: track.id);
      }
    }
    final client = _client;
    if (client == null) {
      throw StateError('Cannot resolve an audio source without a server');
    }
    final requestQuality = effectiveQuality;
    final requestFormat = formatOverride ??
        (kIsWeb && requestQuality != StreamQuality.high ? 'm4a' : null);
    final ticket = await client.requestStreamTicket(
      track.id,
      quality: requestQuality,
      format: requestFormat,
    );
    final url = client.streamUrl(
      track.id,
      ticket.streamToken,
      quality: requestQuality,
      format: requestFormat,
    );
    if (record) {
      _lastSource = PlaybackSourceInfo(
        kind: PlaybackSourceKind.stream,
        quality: requestQuality,
        streamUri: Uri.parse(url),
        sourceBitrateKbps: ticket.sourceBitrateKbps,
        sourceFormat: ticket.sourceFormat,
      );
      notifyListeners();
    }
    return AudioSource.uri(Uri.parse(url), tag: track.id);
  }

  /// Records a file-backed source for the debug overlay, including the file
  /// size so it can derive the effective bitrate of what is actually playing.
  void _recordFileSource(PlaybackSourceKind kind, String path) {
    _lastSource = PlaybackSourceInfo(
      kind: kind,
      quality: effectiveQuality,
      filePath: path,
    );
    notifyListeners();
    final lengthLoader = _host?.localFileLength;
    if (lengthLoader == null) return;
    unawaited(() async {
      try {
        final size = await lengthLoader(path);
        if (size == null) return;
        final current = _lastSource;
        if (current == null ||
            current.kind != kind ||
            current.filePath != path) {
          return;
        }
        _lastSource = PlaybackSourceInfo(
          kind: kind,
          quality: current.quality,
          filePath: path,
          fileSizeBytes: size,
          streamUri: current.streamUri,
          sourceBitrateKbps: current.sourceBitrateKbps,
          sourceFormat: current.sourceFormat,
        );
        notifyListeners();
      } catch (_) {
        // The size stays unknown; the overlay just omits the bitrate.
      }
    }());
  }

  /// Offline, moves [_orderPos] forward (wrapping on repeat-all) until it
  /// lands on a downloaded track. Returns false when nothing in the queue is
  /// available offline.
  bool _advanceToAvailableOffline() {
    final resolver = localFileResolver;
    if (resolver == null) return false;
    for (var step = 0; step < _playOrder.length; step++) {
      final track = _localCurrentTrack;
      if (track == null) return false;
      if (resolver(track.id) != null) return true;
      final next = _nextOrderPosition(_orderPos);
      if (next == null) return false;
      _orderPos = next;
    }
    return false;
  }

  Future<void> _refreshGaplessTail() async {
    _gaplessTailPending = false;
    if (_localPlaybackGuard.isSuspended ||
        _remote != null ||
        !_gapless.isEnabled ||
        _localCurrentTrack == null ||
        (!_offlinePlayback && _client == null)) {
      return;
    }

    final generation = ++_gaplessTailGeneration;
    final expectedOrderPosition = _orderPos;
    var nextOrderPosition = _nextOrderPosition(expectedOrderPosition);
    // A gapless item starts from 0:00; a resuming track must load normally.
    if (nextOrderPosition != null &&
        identical(_queue[_playOrder[nextOrderPosition]], _resumeTrack)) {
      nextOrderPosition = null;
    }

    // Preparing the next source costs a stream-ticket round trip and starts
    // a second competing download, so it waits until the current track has
    // buffered enough headroom. A stale tail is still removed below either
    // way; the position stream re-triggers the append once headroom exists.
    final deferAppend = nextOrderPosition != null &&
        !hasSpeculativeGaplessHeadroom(
          position: _position,
          bufferedPosition: _bufferedPosition,
          duration: _duration,
        );
    // Armed synchronously with the generation bump so the position stream
    // can re-trigger the append even if a guard below returns early.
    _gaplessTailPending = deferAppend;

    AudioSource? nextSource;
    if (nextOrderPosition != null && !deferAppend) {
      try {
        nextSource = await _sourceForOrderPosition(nextOrderPosition);
      } catch (error) {
        debugPrint('[AudioController] Could not prepare gapless track: $error');
      }
    }

    if (generation != _gaplessTailGeneration ||
        !_gapless.isEnabled ||
        _orderPos != expectedOrderPosition) {
      return;
    }

    if (_localPlaybackGuard.isSuspended || _remote != null) return;
    final nativeIndex = _player.currentIndex;
    if (nativeIndex == null ||
        nativeIndex < 0 ||
        nativeIndex >= _nativePlaylistOrderPositions.length) {
      return;
    }

    final removeStart = nativeIndex + 1;
    if (removeStart < _nativePlaylistOrderPositions.length) {
      await _player.removeAudioSourceRange(
        removeStart,
        _nativePlaylistOrderPositions.length,
      );
      if (generation != _gaplessTailGeneration) return;
      _nativePlaylistOrderPositions =
          _nativePlaylistOrderPositions.sublist(0, removeStart);
    }

    if (nextSource != null &&
        nextOrderPosition != null &&
        generation == _gaplessTailGeneration &&
        _orderPos == expectedOrderPosition) {
      await _player.addAudioSource(nextSource);
      _nativePlaylistOrderPositions.add(nextOrderPosition);
    }
  }

  /// Position-stream hook: appends the deferred gapless tail once the
  /// current track has buffered enough headroom.
  void _maybeAppendGaplessTail() {
    if (!_gaplessTailPending || _isLoading) return;
    if (!hasSpeculativeGaplessHeadroom(
      position: _position,
      bufferedPosition: _bufferedPosition,
      duration: _duration,
    )) {
      return;
    }
    // _refreshGaplessTail clears the flag itself; a failed ticket request is
    // not re-armed (matching the pre-existing behaviour where a failed
    // preload falls back to the Dart-driven advance at track end).
    unawaited(_refreshGaplessTail());
  }

  void _onGaplessPreferenceChanged() {
    if (_localCurrentTrack == null || (!_offlinePlayback && _client == null)) {
      return;
    }
    final autoplay = _player.playing;
    final position = _position;
    unawaited(_loadCurrent(
      autoplay: autoplay,
      initialPosition: position,
    ));
  }
}

/// Thrown when a track has no downloaded file while offline playback is on.
class _TrackUnavailableOffline implements Exception {
  _TrackUnavailableOffline(this.track);

  final Track track;

  @override
  String toString() => '"${track.title}" is not downloaded';
}
