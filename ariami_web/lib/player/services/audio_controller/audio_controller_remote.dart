part of '../audio_controller.dart';

List<Track> _tracksFromConnectQueue(List<Map<String, dynamic>> queue) {
  final tracks = <Track>[];
  for (final item in queue) {
    try {
      tracks.add(Track.fromJson(item));
    } catch (_) {
      // Skip tracks another client serialized in a shape this build cannot
      // read; one odd item must not blank the whole mirrored session.
    }
  }
  return List.unmodifiable(tracks);
}

extension _AudioControllerRemote on AudioController {
  /// Hides the mirror immediately when the user starts playback locally, ahead
  /// of the hub confirming the takeover.
  void _suppressRemoteMirror() {
    _invalidateLocalPlayback();
    _remoteSuppressionTimer?.cancel();
    _remoteSuppressionTimer = null;
    _remoteSuppressedAt = DateTime.now();
    if (_remote == null) return;
    _remote = null;
    _remoteTracks = const <Track>[];
    _sendRemoteCommand = null;
    _syncRemoteTicker();
  }

  /// Keeps the mirrored seek bar moving between remote state broadcasts.
  void _syncRemoteTicker() {
    final ticking = _remote?.snapshot.isPlaying ?? false;
    if (ticking && !(_remoteTicker?.isActive ?? false)) {
      _remoteTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _notifyProgress(),
      );
    } else if (!ticking) {
      _remoteTicker?.cancel();
      _remoteTicker = null;
    }
  }

  void _sendRemote(String command, [Map<String, dynamic>? arguments]) =>
      _sendRemoteCommand?.call(command, arguments);

  /// Removes an upcoming item on the active Connect device and adjusts the
  /// mirror optimistically so both desktop queue surfaces respond at once.
  void _removeUpcomingRemote(int upcomingIndex) {
    final remote = _remote;
    if (remote == null || upcomingIndex < 0) return;
    _removeOrderPositionRemote(
        remote.snapshot.currentIndex + 1 + upcomingIndex);
  }

  /// Removes an absolute queue position on the active Connect device and
  /// adjusts the mirror optimistically. The current track may be the target
  /// too — undoing a "play now, keep queue" removes exactly that — in which
  /// case the next track slides into its slot.
  void _removeOrderPositionRemote(int orderPosition) {
    final remote = _remote;
    if (remote == null || orderPosition < 0) return;
    final snapshot = remote.snapshot;
    if (orderPosition < snapshot.currentIndex ||
        orderPosition >= snapshot.queue.length) {
      return;
    }

    final queue = List<Map<String, dynamic>>.from(snapshot.queue);
    final expectedId = queue[orderPosition]['id'] as String?;
    if (expectedId == null || expectedId.isEmpty) return;
    _sendRemote(AriamiConnectCommand.removeQueueIndex, <String, dynamic>{
      'index': orderPosition,
      'id': expectedId,
    });
    queue.removeAt(orderPosition);
    // Removing the playing track lets the next one take its index; clamp for
    // the case where it was the last entry.
    final currentIndex = orderPosition == snapshot.currentIndex
        ? (queue.isEmpty ? -1 : orderPosition.clamp(0, queue.length - 1))
        : snapshot.currentIndex;

    setRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: queue,
      currentIndex: currentIndex,
      positionMs: remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
      castDeviceName: snapshot.castDeviceName,
      updatedAt: DateTime.now().toUtc(),
    )));
  }

  /// Atomically clears every item except Now Playing on the active device.
  void _clearUpcomingRemote(AriamiRemotePlayback remote) {
    final snapshot = remote.snapshot;
    final queue = snapshot.queue;
    if (queue.isEmpty) return;
    final currentIndex = snapshot.currentIndex;
    if (currentIndex < 0 || currentIndex >= queue.length) return;

    _sendRemote(AriamiConnectCommand.clearQueue);

    setRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: <Map<String, dynamic>>[queue[currentIndex]],
      currentIndex: 0,
      positionMs: remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
      castDeviceName: snapshot.castDeviceName,
    )));
  }

  /// Sends a whole new queue to the active device (Spotify-style: browsing on
  /// a controller starts music on the remote player, not here). [ordered] is
  /// the intended play order; the first track starts immediately.
  void _sendRemotePlayContext(
    List<Track> ordered, {
    required bool shuffle,
    List<int>? backingOrder,
    String? sourceId,
    bool forceRepeatAll = false,
  }) {
    final remote = _remote;
    if (remote == null || ordered.isEmpty) return;
    final snapshot = AriamiPlaybackSnapshot(
      queue: ordered.map((t) => t.toConnectJson()).toList(growable: false),
      backingOrder: backingOrder,
      currentIndex: 0,
      positionMs: 0,
      durationMs: ordered.first.duration.inMilliseconds,
      isPlaying: true,
      shuffle: shuffle,
      repeatMode: forceRepeatAll
          ? 'all'
          : repeatModeAfterExplicitTrackChange(remote.snapshot.repeatMode),
      volume: remote.snapshot.volume,
      sourceId: sourceId,
    );
    _sendRemoteSnapshot(remote, snapshot);
  }

  void _sendRemoteSnapshot(
    AriamiRemotePlayback remote,
    AriamiPlaybackSnapshot snapshot,
  ) {
    _sendRemote(AriamiConnectCommand.playContext, <String, dynamic>{
      'snapshot': snapshot.toJson(includeBackingOrder: true),
    });
    _remotePlayNextTail = null;
    // Mirror the new context optimistically; the active device's own state
    // broadcast confirms it.
    setRemoteMirror(remote.copyWithSnapshot(snapshot));
  }

  /// Remote counterpart of [_captureLocalQueueForUndo]: the undo sends the
  /// active device's previous queue back to it, at the same position.
  QueueUndo _captureRemoteQueueForUndo(AriamiRemotePlayback remote) {
    final previous = remote.snapshot;
    final positionMs = remote.positionMs;

    return () async {
      final current = _remote;
      // The user moved playback to another device; don't hijack it.
      if (current == null || current.deviceId != remote.deviceId) return;
      _sendRemoteSnapshot(
        current,
        AriamiPlaybackSnapshot(
          queue: previous.queue,
          backingOrder: previous.backingOrder,
          currentIndex: previous.currentIndex,
          positionMs: positionMs,
          durationMs: previous.durationMs,
          isPlaying: previous.isPlaying,
          shuffle: previous.shuffle,
          repeatMode: previous.repeatMode,
          volume: current.snapshot.volume,
          sourceId: previous.sourceId,
        ),
      );
    };
  }

  /// Remote counterpart of [_playNowKeepingQueue]. The Connect protocol has
  /// no per-track start position, so the interrupted track restarts.
  void _playNowOnRemoteKeepingQueue(AriamiRemotePlayback remote, Track track) {
    final previous = remote.snapshot;
    final index = previous.currentIndex;
    // Shift the pre-shuffle order past the inserted track, which then sits
    // just before the interrupted one there too.
    final order = [
      for (final position in previous.backingOrder)
        position >= index ? position + 1 : position,
    ];
    order.insert(order.indexOf(index + 1), index);
    _sendRemoteSnapshot(
      remote,
      AriamiPlaybackSnapshot(
        queue: [
          ...previous.queue.take(index),
          track.toConnectJson(),
          ...previous.queue.skip(index),
        ],
        backingOrder: order,
        currentIndex: index,
        positionMs: 0,
        durationMs: track.duration.inMilliseconds,
        isPlaying: true,
        shuffle: previous.shuffle,
        repeatMode: previous.repeatMode,
        volume: previous.volume,
        sourceId: previous.sourceId,
      ),
    );
  }

  /// Applies an optimistic local adjustment to the mirrored snapshot so the UI
  /// responds instantly; the active device's next broadcast is authoritative.
  void _applyRemoteOptimistic({
    bool? isPlaying,
    int? positionMs,
    double? volume,
  }) {
    final remote = _remote;
    if (remote == null) return;
    _remote = remote.copyWithSnapshot(remote.snapshot.copyWith(
      // Re-anchor at the currently extrapolated position so toggling
      // play/pause doesn't rewind the bar to the last broadcast position.
      positionMs: positionMs ?? remote.positionMs,
      isPlaying: isPlaying,
      volume: volume,
    ));
    _syncRemoteTicker();
    notifyListeners();
  }

  /// Appends tracks to the active device's mirrored queue and reflects the
  /// result immediately while that device processes the insert commands.
  /// Returns the queue position the first track landed at.
  int _appendRemoteQueue(
    AriamiRemotePlayback remote,
    List<Track> tracks,
  ) {
    final start = remote.snapshot.queue.length;
    _insertRemoteQueueItems(remote, [
      for (var i = 0; i < tracks.length; i++)
        (start + i, tracks[i].toConnectJson()),
    ]);
    return start;
  }

  /// Inserts tracks right after the active device's current track — a
  /// controller's "play next", stacked by this controller's own setting —
  /// and mirrors the result optimistically. Returns the queue position the
  /// first track landed at.
  int _playNextRemote(
    AriamiRemotePlayback remote,
    List<Track> tracks,
  ) {
    final queue = remote.snapshot.queue;
    final tail = _remotePlayNextTail;
    final start = playNextPosition(
      current: remote.snapshot.currentIndex,
      length: queue.length,
      stack: _stackPlayNext,
      tailHint: tail?.$1,
      isTail: tail == null ? null : (i) => queue[i]['id'] == tail.$2,
    );
    _insertRemoteQueueItems(remote, [
      for (var i = 0; i < tracks.length; i++)
        (start + i, tracks[i].toConnectJson()),
    ]);
    _remotePlayNextTail = (start + tracks.length - 1, tracks.last.id);
    return start;
  }

  /// Inserts each (index, track json) in turn on the active device, and
  /// mirrors the result optimistically.
  void _insertRemoteQueueItems(
    AriamiRemotePlayback remote,
    List<(int, Map<String, dynamic>)> items,
  ) {
    if (items.isEmpty) return;
    final snapshot = remote.snapshot;
    final queue = List<Map<String, dynamic>>.from(snapshot.queue);
    for (final (index, trackJson) in items) {
      final at = index.clamp(0, queue.length);
      _sendRemote(AriamiConnectCommand.insertQueueTrack, <String, dynamic>{
        'index': at,
        'track': trackJson,
      });
      queue.insert(at, trackJson);
    }
    setRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: queue,
      currentIndex: snapshot.currentIndex,
      positionMs: remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
      castDeviceName: snapshot.castDeviceName,
    )));
  }
}
