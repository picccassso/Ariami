/// Wire models for Ariami Connect.
///
/// Connect messages contain catalog metadata, never stream URLs or session
/// tokens. Every playback device requests its own short-lived stream ticket.
library;

/// Repeat-one belongs to the currently selected track. An explicit track
/// change keeps repeating enabled, but widens it back to the whole queue.
String repeatModeAfterExplicitTrackChange(String repeatMode) =>
    repeatMode == 'one' ? 'all' : repeatMode;

class AriamiConnectMessageType {
  static const hello = 'connect_hello';
  static const welcome = 'connect_welcome';
  static const devices = 'connect_devices';
  static const state = 'connect_state';
  static const command = 'connect_command';
  static const commandResult = 'connect_command_result';
  static const transfer = 'connect_transfer';
  static const transferResult = 'connect_transfer_result';
  static const rename = 'connect_rename';
  static const error = 'connect_error';
}

/// Longest device display name accepted by the server and rename UIs.
const int kMaxDeviceDisplayNameLength = 40;

/// Normalizes a user-chosen device display name for storage and broadcast:
/// control characters become spaces, runs of whitespace collapse, and the
/// result is trimmed and capped at [kMaxDeviceDisplayNameLength]. Returns
/// null when nothing visible remains, so callers can reject the input.
String? normalizeDeviceDisplayName(String? raw) {
  if (raw == null) return null;
  var name = raw
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (name.length > kMaxDeviceDisplayNameLength) {
    name = name.substring(0, kMaxDeviceDisplayNameLength).trim();
  }
  return name.isEmpty ? null : name;
}

class AriamiConnectCommand {
  static const play = 'play';
  static const pause = 'pause';
  static const toggle = 'toggle';
  static const next = 'next';
  static const previous = 'previous';
  static const seek = 'seek';
  static const setVolume = 'set_volume';
  static const toggleShuffle = 'toggle_shuffle';
  static const cycleRepeat = 'cycle_repeat';

  /// Jumps the active device to an absolute index within the queue it last
  /// published, so a controller can start any track from the mirrored queue.
  static const playQueueIndex = 'play_queue_index';

  /// Replaces the active device's queue with the snapshot in the arguments
  /// and starts it, so browsing on a controller plays on the remote device
  /// (Spotify-style) instead of yanking playback to the controller.
  static const playContext = 'play_context';

  /// Removes the track at an absolute index within the queue the active
  /// device last published, so a controller can edit the mirrored queue.
  /// Arguments: `index` (int) and `id` (String) — the track id the
  /// controller saw at that index, guarding against stale snapshots.
  static const removeQueueIndex = 'remove_queue_index';

  /// Re-inserts a track at an absolute index within the active device's
  /// published queue — a controller's undo of [removeQueueIndex].
  /// Arguments: `index` (int) and `track` (catalog-metadata map).
  static const insertQueueTrack = 'insert_queue_track';

  static const supported = <String>{
    play,
    pause,
    toggle,
    next,
    previous,
    seek,
    setVolume,
    toggleShuffle,
    cycleRepeat,
    playQueueIndex,
    playContext,
    removeQueueIndex,
    insertQueueTrack,
  };
}

class AriamiConnectDevice {
  const AriamiConnectDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.canPlay,
    required this.connectedAt,
    this.isActive = false,
  });

  final String id;
  final String name;
  final String type;
  final bool canPlay;
  final DateTime connectedAt;
  final bool isActive;

  factory AriamiConnectDevice.fromJson(Map<String, dynamic> json) =>
      AriamiConnectDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unknown device',
        type: json['type'] as String? ?? 'unknown',
        canPlay: json['canPlay'] as bool? ?? false,
        connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isActive: json['isActive'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type,
        'canPlay': canPlay,
        'connectedAt': connectedAt.toUtc().toIso8601String(),
        'isActive': isActive,
      };
}

class AriamiPlaybackSnapshot {
  AriamiPlaybackSnapshot({
    required this.queue,
    required this.currentIndex,
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.shuffle,
    required this.repeatMode,
    required this.volume,
    this.sourceId,
    this.updatedAt,
  });

  static const maxQueueLength = 5000;

  final List<Map<String, dynamic>> queue;
  final int currentIndex;
  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final bool shuffle;
  final String repeatMode;
  final double volume;
  final String? sourceId;
  final DateTime? updatedAt;

  String? get currentTrackId {
    if (currentIndex < 0 || currentIndex >= queue.length) return null;
    return queue[currentIndex]['id'] as String?;
  }

  factory AriamiPlaybackSnapshot.fromJson(Map<String, dynamic> json) {
    final rawQueue = json['queue'] as List<dynamic>? ?? const <dynamic>[];
    if (rawQueue.length > maxQueueLength) {
      throw const FormatException('Connect queue is too large');
    }
    final queue = rawQueue
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['id'] as String? ?? '').isNotEmpty)
        .toList(growable: false);
    final rawIndex = (json['currentIndex'] as num?)?.toInt() ?? -1;
    final currentIndex =
        queue.isEmpty ? -1 : rawIndex.clamp(0, queue.length - 1);
    return AriamiPlaybackSnapshot(
      queue: queue,
      currentIndex: currentIndex,
      positionMs:
          ((json['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 86400000),
      durationMs:
          ((json['durationMs'] as num?)?.toInt() ?? 0).clamp(0, 86400000),
      isPlaying: json['isPlaying'] as bool? ?? false,
      shuffle: json['shuffle'] as bool? ?? false,
      repeatMode: switch (json['repeatMode']) {
        'all' => 'all',
        'one' => 'one',
        _ => 'off',
      },
      volume: ((json['volume'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0),
      sourceId: json['sourceId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  AriamiPlaybackSnapshot compensated(DateTime now) {
    final timestamp = updatedAt;
    if (!isPlaying || timestamp == null) return this;
    final elapsed = now.toUtc().difference(timestamp.toUtc()).inMilliseconds;
    if (elapsed <= 0) return this;
    final maximum = durationMs > 0 ? durationMs : 86400000;
    // The compensated position is now anchored at [now]. Handoffs pass through
    // several stages (hub prepare, target prepare, hub commit, target commit),
    // and retaining the original timestamp makes every stage add the same
    // elapsed interval again. That compounds playback drift and can push the
    // target to the end of the track, causing an unexpected skip.
    return copyWith(
      positionMs: (positionMs + elapsed).clamp(0, maximum),
      updatedAt: now.toUtc(),
    );
  }

  AriamiPlaybackSnapshot copyWith({
    int? positionMs,
    bool? isPlaying,
    String? repeatMode,
    double? volume,
    DateTime? updatedAt,
  }) =>
      AriamiPlaybackSnapshot(
        queue: queue,
        currentIndex: currentIndex,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs,
        isPlaying: isPlaying ?? this.isPlaying,
        shuffle: shuffle,
        repeatMode: repeatMode ?? this.repeatMode,
        volume: volume ?? this.volume,
        sourceId: sourceId,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'queue': queue,
        'currentIndex': currentIndex,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isPlaying': isPlaying,
        'shuffle': shuffle,
        'repeatMode': repeatMode,
        'volume': volume,
        if (sourceId != null) 'sourceId': sourceId,
        'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      };
}
