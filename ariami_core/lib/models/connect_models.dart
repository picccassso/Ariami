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

/// The P0 corpus measured the largest supported 5,000-track state and
/// `play_context` messages at about 7.63 MB. Eight MiB keeps that measured
/// maximum valid while putting a hard ceiling in front of JSON decoding.
const int kMaxConnectRawMessageBytes = 8 * 1024 * 1024;

/// A session may have only this many controller commands awaiting a result.
const int kMaxPendingConnectCommands = 64;

/// Completed command results are retained for bounded replay/idempotence.
const int kMaxCompletedConnectCommands = 256;

const int kMaxConnectCommandIdLength = 128;
const int kMaxConnectSourceIdLength = 512;
const int kMaxConnectTrackFields = 20;
const int kMaxConnectTrackFieldNameLength = 40;
const int kMaxConnectTrackStringLength = 1024;

/// Longest string accepted anywhere in a Connect payload. It stays above every
/// per-field track maximum so generic shape validation can never reject
/// metadata that the track rules accept.
const int kMaxConnectStringLength = 2048;

/// Checks the encoded byte ceiling without decoding JSON.
bool isConnectRawMessageWithinLimit(Object? raw) {
  if (raw is! String || raw.length > kMaxConnectRawMessageBytes) return false;
  return utf8.encode(raw).length <= kMaxConnectRawMessageBytes;
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

  /// Playback engines that do not expose programmatic volume control still
  /// support every other Connect command. Controllers may send [setVolume]
  /// to another capable device; this set describes only commands executable
  /// by the device advertising it.
  static const supportedWithoutVolume = <String>{
    play,
    pause,
    toggle,
    next,
    previous,
    seek,
    toggleShuffle,
    cycleRepeat,
    playQueueIndex,
    playContext,
    removeQueueIndex,
    insertQueueTrack,
    clearQueue,
  };
}

/// Rejects hostile or accidentally recursive Connect data before a handler
/// walks it. Command-specific validation below applies tighter shapes.
void validateConnectJsonShape(
  Object? value, {
  int depth = 0,
  int maxDepth = 7,
}) {
  if (depth > maxDepth) {
    throw const FormatException('Connect payload is nested too deeply');
  }
  if (value == null || value is bool || value is num) return;
  if (value is String) {
    if (value.length > kMaxConnectStringLength) {
      throw const FormatException(
          'Connect payload contains an oversized string');
    }
    return;
  }
  if (value is List) {
    if (value.length > AriamiPlaybackSnapshot.maxQueueLength) {
      throw const FormatException('Connect payload contains an oversized list');
    }
    for (final item in value) {
      validateConnectJsonShape(item, depth: depth + 1, maxDepth: maxDepth);
    }
    return;
  }
  if (value is Map) {
    if (value.length > 32) {
      throw const FormatException('Connect payload contains too many fields');
    }
    for (final entry in value.entries) {
      if (entry.key is! String || (entry.key as String).length > 64) {
        throw const FormatException(
            'Connect payload contains an invalid field');
      }
      validateConnectJsonShape(
        entry.value,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
    }
    return;
  }
  throw const FormatException('Connect payload contains an invalid value');
}

/// Validates one catalog track.
///
/// The P0 corpus sized a synthetic worst case, not real tags, and its
/// per-field lengths are far too tight to enforce: a single over-long title
/// anywhere in a queue rejects the whole publication, and the scanner never
/// truncates what it reads from a file. Real libraries carry 200-character
/// medley titles today. These maxima therefore keep several times the measured
/// headroom; [kMaxConnectRawMessageBytes] and [kMaxConnectTrackFields] remain
/// the bounds that actually cap memory.
Map<String, dynamic> validateConnectTrackPayload(Object? raw) {
  if (raw is! Map || raw.length > kMaxConnectTrackFields) {
    throw const FormatException('Invalid Connect track');
  }
  final track = Map<String, dynamic>.from(raw);
  for (final entry in track.entries) {
    if (entry.key.length > kMaxConnectTrackFieldNameLength) {
      throw const FormatException('Invalid Connect track field');
    }
    final value = entry.value;
    if (value is String) {
      final maximum = switch (entry.key) {
        'id' || 'albumId' => 64,
        'modifiedTime' => 64,
        'genre' => 256,
        'title' || 'album' || 'artist' || 'albumArtist' => 512,
        _ => kMaxConnectTrackStringLength,
      };
      if (value.length > maximum) {
        throw FormatException('Connect track ${entry.key} is too long');
      }
    } else if (value != null && value is! num && value is! bool) {
      throw const FormatException('Invalid nested Connect track metadata');
    }
  }
  final id = track['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Invalid Connect track');
  }
  return Map<String, dynamic>.unmodifiable(track);
}

/// Validates the complete snapshot shape used only by v2 state, handoff and
/// `play_context`. The latter deliberately fails as one bounded message; it is
/// not chunked or uploaded out of band.
Map<String, dynamic> validateConnectSnapshotPayload(Object? raw) {
  if (raw is! Map) throw const FormatException('Missing snapshot');
  final snapshot = Map<String, dynamic>.from(raw);
  const allowed = <String>{
    'queue',
    'backingOrder',
    'currentIndex',
    'positionMs',
    'durationMs',
    'isPlaying',
    'shuffle',
    'repeatMode',
    'volume',
    'sourceId',
    'updatedAt',
  };
  if (!allowed.containsAll(snapshot.keys)) {
    throw const FormatException('Invalid Connect snapshot fields');
  }
  final rawQueue = snapshot['queue'];
  if (rawQueue is! List ||
      rawQueue.length > AriamiPlaybackSnapshot.maxQueueLength) {
    throw const FormatException('Connect queue is too large');
  }
  final queue =
      rawQueue.map(validateConnectTrackPayload).toList(growable: false);
  final backingOrder = validateConnectBackingOrder(
    snapshot['backingOrder'],
    queue.length,
  );
  final sourceId = snapshot['sourceId'];
  if (sourceId != null &&
      (sourceId is! String || sourceId.length > kMaxConnectSourceIdLength)) {
    throw const FormatException('Invalid Connect source');
  }
  bool isBoundedInt(Object? value, int min, int max) =>
      value is num &&
      value.isFinite &&
      value == value.toInt() &&
      value >= min &&
      value <= max;

  if ((snapshot.containsKey('currentIndex') &&
          !isBoundedInt(
            snapshot['currentIndex'],
            -1,
            AriamiPlaybackSnapshot.maxQueueLength - 1,
          )) ||
      (snapshot.containsKey('positionMs') &&
          !isBoundedInt(snapshot['positionMs'], 0, 86400000)) ||
      (snapshot.containsKey('durationMs') &&
          !isBoundedInt(snapshot['durationMs'], 0, 86400000)) ||
      (snapshot.containsKey('isPlaying') && snapshot['isPlaying'] is! bool) ||
      (snapshot.containsKey('shuffle') && snapshot['shuffle'] is! bool)) {
    throw const FormatException('Invalid Connect snapshot state');
  }
  final repeatMode = snapshot['repeatMode'];
  if (repeatMode != null && !const {'off', 'all', 'one'}.contains(repeatMode)) {
    throw const FormatException('Invalid Connect repeat mode');
  }
  final volume = snapshot['volume'];
  if (volume != null &&
      (volume is! num || !volume.isFinite || volume < 0 || volume > 1)) {
    throw const FormatException('Invalid Connect volume');
  }
  final updatedAt = snapshot['updatedAt'];
  if (updatedAt != null &&
      (updatedAt is! String ||
          updatedAt.length > 64 ||
          DateTime.tryParse(updatedAt) == null)) {
    throw const FormatException('Invalid Connect timestamp');
  }
  final parsed = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
    ...snapshot,
    'queue': queue,
    'backingOrder': backingOrder,
  });
  return Map<String, dynamic>.unmodifiable(
    parsed.toJson(includeBackingOrder: snapshot.containsKey('backingOrder')),
  );
}

/// Returns an immutable, normalized argument map for a supported command.
/// Every command has an explicit shape so arbitrary nesting cannot hide below
/// an otherwise small envelope.
Map<String, dynamic> validateConnectCommandArguments(
  String command,
  Object? raw,
) {
  if (raw is! Map) throw const FormatException('Invalid command arguments');
  final arguments = Map<String, dynamic>.from(raw);

  void requireKeys(Set<String> keys) {
    if (arguments.length != keys.length || !keys.containsAll(arguments.keys)) {
      throw const FormatException('Invalid command arguments');
    }
  }

  int requireInt(String key, {required int min, required int max}) {
    final value = arguments[key];
    if (value is! num || !value.isFinite || value != value.toInt()) {
      throw const FormatException('Invalid command arguments');
    }
    final integer = value.toInt();
    if (integer < min || integer > max) {
      throw const FormatException('Invalid command arguments');
    }
    return integer;
  }

  switch (command) {
    case AriamiConnectCommand.play:
    case AriamiConnectCommand.pause:
    case AriamiConnectCommand.toggle:
    case AriamiConnectCommand.next:
    case AriamiConnectCommand.previous:
    case AriamiConnectCommand.toggleShuffle:
    case AriamiConnectCommand.cycleRepeat:
    case AriamiConnectCommand.clearQueue:
      requireKeys(const <String>{});
      return const <String, dynamic>{};
    case AriamiConnectCommand.seek:
      requireKeys(const <String>{'positionMs'});
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'positionMs': requireInt('positionMs', min: 0, max: 86400000),
      });
    case AriamiConnectCommand.setVolume:
      requireKeys(const <String>{'volume'});
      final volume = arguments['volume'];
      if (volume is! num || !volume.isFinite || volume < 0 || volume > 1) {
        throw const FormatException('Invalid command arguments');
      }
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'volume': volume.toDouble(),
      });
    case AriamiConnectCommand.playQueueIndex:
      requireKeys(const <String>{'index'});
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'index': requireInt(
          'index',
          min: 0,
          max: AriamiPlaybackSnapshot.maxQueueLength - 1,
        ),
      });
    case AriamiConnectCommand.removeQueueIndex:
      requireKeys(const <String>{'index', 'id'});
      final id = arguments['id'];
      if (id is! String || id.isEmpty || id.length > 64) {
        throw const FormatException('Invalid command arguments');
      }
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'index': requireInt(
          'index',
          min: 0,
          max: AriamiPlaybackSnapshot.maxQueueLength - 1,
        ),
        'id': id,
      });
    case AriamiConnectCommand.insertQueueTrack:
      requireKeys(const <String>{'index', 'track'});
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'index': requireInt(
          'index',
          min: 0,
          max: AriamiPlaybackSnapshot.maxQueueLength,
        ),
        'track': validateConnectTrackPayload(arguments['track']),
      });
    case AriamiConnectCommand.playContext:
      requireKeys(const <String>{'snapshot'});
      return Map<String, dynamic>.unmodifiable(<String, dynamic>{
        'snapshot': validateConnectSnapshotPayload(arguments['snapshot']),
      });
    default:
      throw const FormatException('Unsupported Connect command');
  }
}

/// Recursively freezes a JSON payload before the hub retains it for later
/// delivery. This prevents a caller-owned map from mutating in-flight work.
Object? immutableConnectJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(<String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: immutableConnectJson(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(immutableConnectJson));
  }
  return value;
}

class AriamiConnectDevice {
  const AriamiConnectDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.canPlay,
    required this.connectedAt,
    this.isActive = false,
    this.supportedCommands = AriamiConnectCommand.supported,
  });

  final String id;
  final String name;
  final String type;
  final bool canPlay;
  final DateTime connectedAt;
  final bool isActive;
  final Set<String> supportedCommands;

  factory AriamiConnectDevice.fromJson(Map<String, dynamic> json) =>
      AriamiConnectDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unknown device',
        type: json['type'] as String? ?? 'unknown',
        canPlay: json['canPlay'] as bool? ?? false,
        connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isActive: json['isActive'] as bool? ?? false,
        supportedCommands: _readSupportedConnectCommands(json),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type,
        'canPlay': canPlay,
        'connectedAt': connectedAt.toUtc().toIso8601String(),
        'isActive': isActive,
        'supportedCommands': supportedCommands.toList(growable: false)..sort(),
      };
}

Set<String> _readSupportedConnectCommands(Map<String, dynamic> json) {
  if (!json.containsKey('supportedCommands')) {
    return AriamiConnectCommand.supported;
  }
  final raw = json['supportedCommands'];
  if (raw is! List) return const <String>{};
  return Set<String>.unmodifiable(
    raw.whereType<String>().where(AriamiConnectCommand.supported.contains),
  );
}

class AriamiPlaybackSnapshot {
  factory AriamiPlaybackSnapshot({
    required List<Map<String, dynamic>> queue,
    List<int>? backingOrder,
    required int currentIndex,
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
    required bool shuffle,
    required String repeatMode,
    required double volume,
    String? sourceId,
    DateTime? updatedAt,
  }) {
    return AriamiPlaybackSnapshot._validated(
      queue: queue,
      backingOrder: validateConnectBackingOrder(backingOrder, queue.length),
      currentIndex: currentIndex,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      shuffle: shuffle,
      repeatMode: repeatMode,
      volume: volume,
      sourceId: sourceId,
      updatedAt: updatedAt,
    );
  }

  AriamiPlaybackSnapshot._validated({
    required this.queue,
    required this.backingOrder,
    required this.currentIndex,
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.shuffle,
    required this.repeatMode,
    required this.volume,
    required this.sourceId,
    required this.updatedAt,
  });

  /// Builds from queue data already owned and validated by a playback engine.
  /// The list identities are retained so Connect can cache queue fingerprints
  /// across position-only snapshots.
  factory AriamiPlaybackSnapshot.fromValidatedQueue({
    required List<Map<String, dynamic>> queue,
    required List<int> backingOrder,
    required int currentIndex,
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
    required bool shuffle,
    required String repeatMode,
    required double volume,
    String? sourceId,
    DateTime? updatedAt,
  }) {
    if (queue.length > maxQueueLength || backingOrder.length != queue.length) {
      throw const FormatException('Invalid Connect queue state');
    }
    return AriamiPlaybackSnapshot._validated(
      queue: queue,
      backingOrder: backingOrder,
      currentIndex: currentIndex,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      shuffle: shuffle,
      repeatMode: repeatMode,
      volume: volume,
      sourceId: sourceId,
      updatedAt: updatedAt,
    );
  }

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

  /// Decodes a v3 progress message while retaining the already-validated
  /// queue objects received in the matching `connect_queue` message.
  ///
  /// A normal progress tick changes only scalar playback state. Copying every
  /// track map and revalidating the full backing permutation on each tick puts
  /// queue-sized work back on Flutter's UI isolate, defeating the v3 split.
  factory AriamiPlaybackSnapshot.fromSplitState(
    Map<String, dynamic> json, {
    required List<Map<String, dynamic>> queue,
    required List<int> backingOrder,
    required String? sourceId,
  }) {
    if (queue.length > maxQueueLength || backingOrder.length != queue.length) {
      throw const FormatException('Invalid Connect queue state');
    }
    final rawIndex = (json['currentIndex'] as num?)?.toInt() ?? -1;
    return AriamiPlaybackSnapshot._validated(
      queue: queue,
      backingOrder: backingOrder,
      currentIndex: queue.isEmpty ? -1 : rawIndex.clamp(0, queue.length - 1),
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
      sourceId: sourceId,
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
      AriamiPlaybackSnapshot._validated(
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
