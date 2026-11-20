part of '../audio_controller.dart';

/// Where removed queue items go back on undo: their old play-order positions,
/// but never before [floor] (the first upcoming slot), so an undo after
/// playback moved on never interrupts the current track. Order is preserved.
List<(int, T)> _undoInsertions<T>(List<(int, T)> removed, int floor) {
  final insertions = <(int, T)>[];
  for (final (position, item) in removed) {
    final at = max(position, floor);
    insertions.add((at, item));
    floor = at + 1;
  }
  return insertions;
}

extension _AudioControllerQueueUndo on AudioController {
  /// Whether the queue about to be replaced by [tracks] still has tracks
  /// lined up. Hopping within the same collection doesn't count.
  bool _queueWorthKeeping(List<Track> tracks, String? sourceId) {
    final remote = _remote;
    if (remote != null) {
      final snapshot = remote.snapshot;
      return snapshot.currentIndex < snapshot.queue.length - 1 &&
          !_isSameQueueContext(
            snapshot.sourceId,
            _remoteTracks,
            sourceId,
            tracks,
          );
    }
    return _orderPos >= 0 &&
        _orderPos < _playOrder.length - 1 &&
        !_isSameQueueContext(_sourceId, _queue, sourceId, tracks);
  }

  /// Whether the collection [tracks] from [sourceId] is the one already queued.
  bool _isSameQueueContext(
    String? previousSourceId,
    List<Track> previousTracks,
    String? sourceId,
    List<Track> tracks,
  ) {
    if (sourceId != null && sourceId == previousSourceId) return true;
    if (tracks.length != previousTracks.length) return false;
    final previousIds = previousTracks.map((track) => track.id).toSet();
    return tracks.every((track) => previousIds.contains(track.id));
  }

  /// Called before Play/Shuffle replaces the queue with [tracks]: publishes an
  /// undo when tracks that were lined up are about to be lost.
  void _offerQueueReplacementUndo(List<Track> tracks, String? sourceId) {
    if (_queueReplacedController.isClosed ||
        !_queueWorthKeeping(tracks, sourceId)) {
      return;
    }
    final remote = _remote;
    _queueReplacedController.add(
      remote != null
          ? _captureRemoteQueueForUndo(remote)
          : _captureLocalQueueForUndo(),
    );
  }

  QueueUndo _captureLocalQueueForUndo() {
    final queue = List<Track>.of(_queue);
    final playOrder = List<int>.of(_playOrder);
    final orderPos = _orderPos;
    final shuffle = _shuffle;
    final repeat = _repeat;
    final sourceId = _sourceId;
    final position = _position;
    final wasPlaying = _isPlaying;

    return () async {
      // Another device took over in the meantime; its queue is not ours.
      if (_remote != null) return;
      _suppressRemoteMirror();
      _replaceQueue(queue);
      _playOrder = List<int>.of(playOrder);
      _orderPos = orderPos;
      _shuffle = shuffle;
      _repeat = repeat;
      _sourceId = sourceId;
      await _loadCurrent(autoplay: wasPlaying, initialPosition: position);
    };
  }

  /// Plays [track] now and keeps the queue after it; the interrupted track
  /// resumes where it stopped once [track] ends.
  Future<void> _playNowKeepingQueue(Track track) async {
    final remote = _remote;
    if (remote != null) {
      _playNowOnRemoteKeepingQueue(remote, track);
      return;
    }
    _suppressRemoteMirror();
    if (_repeat == PlayerRepeatMode.one) {
      _repeat = PlayerRepeatMode.all;
    }
    _resumeTrack = _localCurrentTrack;
    _resumeTrackPosition = _position;
    // A fresh instance, so the resume match (by identity) never hits it.
    _queue.add(track.copyWith());
    _playOrder.insert(_orderPos, _queue.length - 1);
    await _loadCurrent(autoplay: true);
  }

  /// Returns an undo that puts back the tracks at [orderPositions] (ascending,
  /// in range), captured before they are removed.
  QueueUndo? _captureRemovalUndo(List<int> orderPositions) {
    if (orderPositions.isEmpty) return null;
    final remote = _remote;
    if (remote != null) {
      final removed = [
        for (final position in orderPositions)
          (position, remote.snapshot.queue[position]),
      ];
      return () async {
        final current = _remote;
        // Playback moved to another device; don't edit its queue.
        if (current == null || current.deviceId != remote.deviceId) return;
        _insertRemoteQueueItems(
          current,
          _undoInsertions(removed, current.snapshot.currentIndex + 1),
        );
      };
    }
    final removed = [
      for (final position in orderPositions)
        (position, _queue[_playOrder[position]]),
    ];
    return () async {
      if (_remote != null) return;
      for (final (position, track) in _undoInsertions(removed, _orderPos + 1)) {
        await _insertOrderPositionLocal(position, track);
      }
    };
  }
}
