/// Wire models for Ariami Connect.
///
/// Connect messages contain catalog metadata, never stream URLs or session
/// tokens. Every playback device requests its own short-lived stream ticket.
library;

import 'dart:convert';

/// Protocol versions this client can speak, in preference order.
///
class AriamiConnectProtocol {
  static const int v2 = 2;
  static const int v3 = 3;
  static const List<int> supportedVersions = <int>[v3, v2];
}

/// Repeat-one belongs to the currently selected track. An explicit track
/// change keeps repeating enabled, but widens it back to the whole queue.
String repeatModeAfterExplicitTrackChange(String repeatMode) =>
    repeatMode == 'one' ? 'all' : repeatMode;

class AriamiConnectMessageType {
  static const hello = 'connect_hello';
  static const welcome = 'connect_welcome';
  static const devices = 'connect_devices';
  static const queue = 'connect_queue';
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

  /// Removes every queue entry except the currently playing track atomically.
  /// This avoids index races from sending several remove commands at once.
  static const clearQueue = 'clear_queue';

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
    clearQueue,
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
    List<int>? backingOrder,
    required this.currentIndex,
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.shuffle,
    required this.repeatMode,
    required this.volume,
    this.sourceId,
    this.updatedAt,
  }) : backingOrder = validateConnectBackingOrder(backingOrder, queue.length);

  static const maxQueueLength = 5000;

  final List<Map<String, dynamic>> queue;

  /// Positional permutation into [queue] that reconstructs the pre-shuffle
  /// order. Positions, rather than track IDs, keep duplicate occurrences
  /// distinct across handoffs.
  final List<int> backingOrder;
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
      backingOrder: validateConnectBackingOrder(
        json['backingOrder'],
        queue.length,
      ),
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
        backingOrder: backingOrder,
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

  /// Version-2 snapshot encoding. [includeBackingOrder] is used only by
  /// upgraded handoff payloads; ordinary v2 state remains byte-shape
  /// compatible and cannot claim an order it never supplied.
  Map<String, dynamic> toJson({bool includeBackingOrder = false}) =>
      <String, dynamic>{
        'queue': queue,
        if (includeBackingOrder) 'backingOrder': backingOrder,
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

  /// Computed once per snapshot. Publishing consults the fingerprint several
  /// times per progress tick, and canonicalizing a full queue is far too
  /// expensive to repeat on the playback device's UI isolate.
  late final String queueFingerprint = canonicalConnectQueueFingerprint(
    queue: queue,
    backingOrder: backingOrder,
    sourceId: sourceId,
  );
}

/// Returns a complete permutation for [length], defaulting absent v2 data to
/// identity order. Malformed positional data is rejected rather than silently
/// corrupting shuffle restoration.
List<int> validateConnectBackingOrder(Object? raw, int length) {
  if (raw == null) return List<int>.generate(length, (index) => index);
  if (raw is! List || raw.length != length) {
    throw const FormatException('Invalid Connect backing order');
  }
  final order = <int>[];
  final seen = <int>{};
  for (final value in raw) {
    if (value is! num || value != value.toInt()) {
      throw const FormatException('Invalid Connect backing order');
    }
    final index = value.toInt();
    if (index < 0 || index >= length || !seen.add(index)) {
      throw const FormatException('Invalid Connect backing order');
    }
    order.add(index);
  }
  return List<int>.unmodifiable(order);
}

/// Converts a play order — queue indices in resolved play order — into the
/// backing order the wire carries: positions into the resolved array, listed
/// in backing-queue order. Indices the play order never references are
/// dropped, so the result stays a complete permutation of what was resolved.
List<int> connectBackingOrderFor(List<int> resolvedOrder, int queueLength) {
  final positions = List<int>.filled(queueLength, -1);
  for (var position = 0; position < resolvedOrder.length; position++) {
    final queueIndex = resolvedOrder[position];
    if (positions[queueIndex] < 0) positions[queueIndex] = position;
  }
  return positions.where((position) => position >= 0).toList(growable: false);
}

/// Stable fingerprint of the canonical queue identity. Map keys are sorted so
/// equivalent track metadata cannot spuriously advance the queue counter just
/// because a client serialized keys in a different insertion order.
String canonicalConnectQueueFingerprint({
  required List<Map<String, dynamic>> queue,
  required List<int> backingOrder,
  required String? sourceId,
}) =>
    jsonEncode(<String, dynamic>{
      'tracks': _canonicalConnectJson(queue),
      'backingOrder': backingOrder,
      'sourceId': sourceId,
    });

Object? _canonicalConnectJson(Object? value) {
  if (value is List) return value.map(_canonicalConnectJson).toList();
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalConnectJson(value[key]),
    };
  }
  return value;
}
