part of 'playback_manager.dart';

extension _PlaybackManagerConnectImpl on PlaybackManager {
  /// Wires (or clears) the remote mirror. Called by the Connect controller on
  /// every hub update; [remote] is null whenever this device is the active
  /// player or no remote session exists.
  void _setConnectRemoteMirrorImpl(
    AriamiRemotePlayback? remote, {
    void Function(String command, [Map<String, dynamic>? arguments])?
        sendCommand,
  }) {
    if (remote == null) {
      _connectSuppressedAt = null;
      _connectSuppressionTimer?.cancel();
      _connectSuppressionTimer = null;
    }
    if (remote != null && _connectSuppressedAt != null) {
      final sinceIntent = DateTime.now().difference(_connectSuppressedAt!);
      if (sinceIntent < PlaybackManager._connectSuppression) {
        _connectSuppressionTimer?.cancel();
        _connectSuppressionTimer = Timer(
          PlaybackManager._connectSuppression - sinceIntent,
          () {
            _connectSuppressionTimer = null;
            _connectSuppressedAt = null;
            setConnectRemoteMirror(remote, sendCommand: sendCommand);
          },
        );
        return;
      }
      _connectSuppressedAt = null;
    }
    _sendConnectCommand = sendCommand ?? _sendConnectCommand;
    final unchanged = identical(_connectRemote?.snapshot, remote?.snapshot) &&
        _connectRemote?.deviceId == remote?.deviceId;
    _connectRemote = remote;
    if (remote == null) {
      _sendConnectCommand = null;
      _connectRemoteSongs = const <Song>[];
      _connectRemoteQueue = null;
    } else {
      final incoming = remote.snapshot.queue
          .map(_songFromConnectJson)
          .whereType<Song>()
          .toList(growable: false);
      // Broadcasts arrive continuously while the remote device plays
      // (position ticks), so an unchanged queue must keep its previous Song
      // instances: queue rows are keyed by object identity, and fresh
      // instances would recreate every row and re-load its artwork.
      final sameSongs = _sameSongSequence(_connectRemoteSongs, incoming);
      final songs = sameSongs ? _connectRemoteSongs : incoming;
      final currentIndex = songs.isEmpty
          ? 0
          : remote.snapshot.currentIndex.clamp(0, songs.length - 1);
      _connectRemoteSongs = songs;
      if (!sameSongs ||
          _connectRemoteQueue == null ||
          _connectRemoteQueue!.currentIndex != currentIndex) {
        _connectRemoteQueue = PlaybackQueue(
          songs: List<Song>.from(songs),
          currentIndex: currentIndex,
        );
      }
    }
    _syncConnectTicker();
    if (!unchanged) _notifyStateChanged();
  }

  /// Whether both lists hold the same songs in the same order, so the
  /// mirrored queue can keep its existing instances across a broadcast.
  bool _sameSongSequence(List<Song> previous, List<Song> incoming) {
    if (previous.length != incoming.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].id != incoming[i].id) return false;
    }
    return true;
  }

  /// Hides the mirror immediately when the user starts playback locally, ahead
  /// of the hub confirming the takeover.
  void _suppressConnectMirror() {
    _connectSuppressionTimer?.cancel();
    _connectSuppressionTimer = null;
    _connectSuppressedAt = DateTime.now();
    if (_connectRemote == null) return;
    _connectRemote = null;
    _connectRemoteSongs = const <Song>[];
    _connectRemoteQueue = null;
    _sendConnectCommand = null;
    _syncConnectTicker();
  }

  /// Keeps the mirrored seek bar moving between remote state broadcasts.
  void _syncConnectTicker() {
    final ticking = _connectRemote?.snapshot.isPlaying ?? false;
    if (ticking && !(_connectTicker?.isActive ?? false)) {
      _connectTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _notifyStateChanged(),
      );
    } else if (!ticking) {
      _connectTicker?.cancel();
      _connectTicker = null;
    }
  }

  void _sendConnect(String command, [Map<String, dynamic>? arguments]) =>
      _sendConnectCommand?.call(command, arguments);

  /// Sends a whole new queue to the active device (Spotify-style: browsing on
  /// a controller starts music on the remote player, not here).
  void _sendConnectPlayContext(
    List<Song> songs, {
    int currentIndex = 0,
    required bool shuffle,
    bool forceRepeatAll = false,
  }) {
    final remote = _connectRemote;
    if (remote == null || songs.isEmpty) return;
    final start = currentIndex.clamp(0, songs.length - 1);
    final snapshot = AriamiPlaybackSnapshot(
      queue: songs.map((song) => song.toJson()).toList(growable: false),
      currentIndex: start,
      positionMs: 0,
      durationMs: songs[start].duration.inMilliseconds,
      isPlaying: true,
      shuffle: shuffle,
      repeatMode: forceRepeatAll
          ? 'all'
          : repeatModeAfterExplicitTrackChange(remote.snapshot.repeatMode),
      volume: remote.snapshot.volume,
    );
    _sendConnect(AriamiConnectCommand.playContext, <String, dynamic>{
      'snapshot': snapshot.toJson(),
    });
    // Mirror the new context optimistically; the active device's own state
    // broadcast confirms it.
    setConnectRemoteMirror(remote.copyWithSnapshot(snapshot));
  }

  /// Removes a track from the mirrored queue: sends the edit to the active
  /// device and applies it optimistically (the device's next state broadcast
  /// is authoritative). Returns a removal snapshot for the undo toast.
  QueueItemRemoval? _removeConnectQueueItem(
    AriamiRemotePlayback remote,
    int index,
  ) {
    final snapshot = remote.snapshot;
    if (index < 0 ||
        index >= snapshot.queue.length ||
        index >= _connectRemoteSongs.length) {
      return null;
    }
    final song = _connectRemoteSongs[index];

    _sendConnect(AriamiConnectCommand.removeQueueIndex, <String, dynamic>{
      'index': index,
      'id': song.id,
    });

    final wasCurrent = index == snapshot.currentIndex;
    final queue = List<Map<String, dynamic>>.from(snapshot.queue)
      ..removeAt(index);
    var currentIndex = snapshot.currentIndex;
    if (index < currentIndex) currentIndex--;
    if (currentIndex >= queue.length) currentIndex = queue.length - 1;
    setConnectRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: queue,
      currentIndex: currentIndex,
      positionMs: wasCurrent ? 0 : remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
    )));

    return QueueItemRemoval(
      song: song,
      index: index,
      wasCurrent: wasCurrent,
      wasPlaying: snapshot.isPlaying,
      wasOneShot: false,
      wasRemote: true,
    );
  }

  /// Sends a controller's undo of a mirrored-queue removal back to the active
  /// device and re-inserts the track into the mirror optimistically.
  void _undoConnectQueueRemoval(QueueItemRemoval removal) {
    final remote = _connectRemote;
    if (remote == null) return;
    final trackJson = removal.song.toJson();

    _sendConnect(AriamiConnectCommand.insertQueueTrack, <String, dynamic>{
      'index': removal.index,
      'track': trackJson,
    });

    final snapshot = remote.snapshot;
    final queue = List<Map<String, dynamic>>.from(snapshot.queue);
    final clamped = removal.index.clamp(0, queue.length);
    queue.insert(clamped, trackJson);
    var currentIndex = snapshot.currentIndex;
    if (removal.wasCurrent) {
      // Undoing a removed now-playing track makes it current again.
      currentIndex = clamped;
    } else if (clamped <= currentIndex) {
      currentIndex++;
    }
    setConnectRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: queue,
      currentIndex: currentIndex,
      positionMs: removal.wasCurrent ? 0 : remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
    )));
  }

  /// Appends songs to the active device's mirrored queue and reflects the
  /// change immediately while that device processes the insert commands.
  void _appendConnectQueue(
    AriamiRemotePlayback remote,
    List<Song> songs,
  ) {
    if (songs.isEmpty) return;
    final snapshot = remote.snapshot;
    final queue = List<Map<String, dynamic>>.from(snapshot.queue);
    for (final song in songs) {
      final index = queue.length;
      final track = song.toJson();
      _sendConnect(AriamiConnectCommand.insertQueueTrack, <String, dynamic>{
        'index': index,
        'track': track,
      });
      queue.add(track);
    }
    setConnectRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: queue,
      currentIndex: snapshot.currentIndex,
      positionMs: remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
    )));
  }

  /// Atomically clears every item except Now Playing on the active device.
  void _clearConnectQueue(AriamiRemotePlayback remote) {
    final snapshot = remote.snapshot;
    final queue = snapshot.queue;
    if (queue.isEmpty) return;
    final currentIndex = snapshot.currentIndex;
    if (currentIndex < 0 || currentIndex >= queue.length) return;

    _sendConnect(AriamiConnectCommand.clearQueue);

    setConnectRemoteMirror(remote.copyWithSnapshot(AriamiPlaybackSnapshot(
      queue: <Map<String, dynamic>>[queue[currentIndex]],
      currentIndex: 0,
      positionMs: remote.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying,
      shuffle: snapshot.shuffle,
      repeatMode: snapshot.repeatMode,
      volume: snapshot.volume,
      sourceId: snapshot.sourceId,
    )));
  }

  /// Applies an optimistic local adjustment to the mirrored snapshot so the UI
  /// responds instantly; the active device's next broadcast is authoritative.
  void _applyConnectOptimistic({bool? isPlaying, int? positionMs}) {
    final remote = _connectRemote;
    if (remote == null) return;
    _connectRemote = remote.copyWithSnapshot(remote.snapshot.copyWith(
      // Re-anchor at the currently extrapolated position so toggling
      // play/pause doesn't rewind the bar to the last broadcast position.
      positionMs: positionMs ?? remote.positionMs,
      isPlaying: isPlaying,
    ));
    _syncConnectTicker();
    _notifyStateChanged();
  }

  /// Runs a Connect command against the local engine, bypassing the remote
  /// mirror. The hub only routes commands here for this device's own playback
  /// (including the takeover pause sent to a device that just lost the
  /// session), so they must never bounce back out as remote commands.
  Future<void> _handleConnectCommandImpl(
    String command,
    Map<String, dynamic> arguments,
  ) async {
    switch (command) {
      case AriamiConnectCommand.play:
        if (!_localIsPlaying) await _togglePlayPauseImpl();
      case AriamiConnectCommand.pause:
        if (_localIsPlaying) await _togglePlayPauseImpl();
      case AriamiConnectCommand.toggle:
        await _togglePlayPauseImpl();
      case AriamiConnectCommand.next:
        await _skipNextImpl(completedNaturally: false);
      case AriamiConnectCommand.previous:
        await _skipPreviousImpl();
      case AriamiConnectCommand.seek:
        await _seekImpl(Duration(
          milliseconds: (arguments['positionMs'] as num?)?.toInt() ?? 0,
        ));
      case AriamiConnectCommand.toggleShuffle:
        _toggleShuffleImpl();
      case AriamiConnectCommand.cycleRepeat:
        _toggleRepeatImpl();
      case AriamiConnectCommand.playQueueIndex:
        await _skipToQueueItemImpl(
          (arguments['index'] as num?)?.toInt() ?? -1,
        );
      case AriamiConnectCommand.removeQueueIndex:
        await _removeQueueItemForConnect(
          (arguments['index'] as num?)?.toInt() ?? -1,
          arguments['id'] as String?,
        );
      case AriamiConnectCommand.insertQueueTrack:
        final rawTrack = arguments['track'];
        if (rawTrack is Map) {
          final song =
              _songFromConnectJson(Map<String, dynamic>.from(rawTrack));
          if (song != null) {
            _insertQueueItemImpl(
              (arguments['index'] as num?)?.toInt() ?? _queue.length,
              song,
            );
          }
        }
      case AriamiConnectCommand.clearQueue:
        await _clearUpcomingImpl();
      case AriamiConnectCommand.playContext:
        final raw = arguments['snapshot'];
        if (raw is Map) {
          final snapshot = AriamiPlaybackSnapshot.fromJson(
            Map<String, dynamic>.from(raw),
          );
          await applyConnectSnapshot(
            snapshot.copyWith(
              repeatMode:
                  repeatModeAfterExplicitTrackChange(snapshot.repeatMode),
            ),
          );
        }
    }
  }

  /// Always pauses this device's own playback (local or cast), bypassing the
  /// remote mirror; used for Connect handoffs.
  Future<void> _pauseLocalImpl() async {
    if (_localIsPlaying) await _togglePlayPauseImpl();
  }

  Future<void> _applyConnectSnapshotImpl(
      AriamiPlaybackSnapshot snapshot) async {
    final songs = snapshot.queue
        .map(_songFromConnectJson)
        .whereType<Song>()
        .toList(growable: false);
    if (songs.isEmpty) return;
    await _audioPlayer.pause();
    _invalidatePendingRestore('ariami-connect');
    _queue = PlaybackQueue(
      songs: songs,
      currentIndex: snapshot.currentIndex.clamp(0, songs.length - 1),
    );
    _oneShotQueuedSongs.clear();
    _shuffleService.reset();
    _isShuffleEnabled = snapshot.shuffle;
    _repeatMode = switch (snapshot.repeatMode) {
      'all' => RepeatMode.all,
      'one' => RepeatMode.one,
      _ => RepeatMode.none,
    };
    _restoredPosition = Duration(milliseconds: snapshot.positionMs);
    _pendingUiPosition = _restoredPosition;
    await _playCurrentSong(autoPlay: snapshot.isPlaying);
    await _saveState();
    _notifyStateChanged();
  }

  Song? _songFromConnectJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final durationSeconds = (json['duration'] as num?)?.toInt() ??
        (((json['durationMs'] as num?)?.toInt() ?? 0) ~/ 1000);
    return Song(
      id: id,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String?,
      albumId: json['albumId'] as String?,
      albumArtist: json['albumArtist'] as String?,
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      genre: json['genre'] as String?,
      duration: Duration(seconds: durationSeconds),
      filePath: json['filePath'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
