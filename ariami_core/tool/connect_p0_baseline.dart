import 'dart:convert';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';

/// Canonical wire timestamp for every measured message. Byte counts must not
/// depend on `DateTime.now()`: its ISO-8601 form omits the microsecond triple
/// whenever the microsecond component is zero, which shortens a message by
/// three bytes roughly once in a thousand.
const connectP0WireTimestamp = '2026-01-02T03:04:05.123456';
const _snapshotTimestamp = '2026-01-02T03:04:05.123456Z';

Map<String, dynamic> _track(int index, {required bool largeMetadata}) {
  String padded(String value, int length) =>
      value.padRight(length, value.substring(value.length - 1));

  return <String, dynamic>{
    'id': largeMetadata ? padded('track-$index-', 64) : 'track-$index',
    'title': largeMetadata ? padded('Title $index ', 200) : 'Track $index',
    'artist': largeMetadata ? padded('Artist $index ', 160) : 'Artist $index',
    'album':
        largeMetadata ? padded('Album $index ', 200) : 'Album ${index ~/ 12}',
    'albumId': largeMetadata
        ? padded('album-${index ~/ 12}-', 64)
        : 'album-${index ~/ 12}',
    'albumArtist':
        largeMetadata ? padded('Album Artist $index ', 160) : 'Album Artist',
    'trackNumber': (index % 99) + 1,
    'discNumber': (index % 4) + 1,
    'year': 2026,
    'genre': largeMetadata ? padded('Genre ', 80) : 'Electronic',
    'duration': 3600,
    'filePath': largeMetadata
        ? '/music/${padded('folder-$index-', 180)}/${padded('file-$index-', 180)}.flac'
        : '/music/track-$index.flac',
    'fileSize': 999999999,
    'modifiedTime': _snapshotTimestamp,
  };
}

/// Builds the deterministic queue shape used by the P0 traffic measurements.
AriamiPlaybackSnapshot buildConnectP0Snapshot(
  int queueLength, {
  required bool largeMetadata,
  int positionMs = 0,
}) =>
    AriamiPlaybackSnapshot(
      queue: List<Map<String, dynamic>>.generate(
        queueLength,
        (index) => _track(index, largeMetadata: largeMetadata),
        growable: false,
      ),
      currentIndex: queueLength ~/ 2,
      positionMs: positionMs,
      durationMs: 3600000,
      isPlaying: true,
      shuffle: true,
      repeatMode: 'all',
      volume: 0.75,
      sourceId: 'playlist:connect-p0-baseline',
      updatedAt: DateTime.parse(_snapshotTimestamp),
    );

int _wireBytes(WsMessage message) =>
    utf8.encode(jsonEncode(message.toJson())).length;

Map<String, dynamic> buildConnectP0Measurements() {
  final representative = buildConnectP0Snapshot(500, largeMetadata: false);
  final statePublication = WsMessage(
    type: AriamiConnectMessageType.state,
    data: <String, dynamic>{
      'activate': false,
      'snapshot': representative.toJson(),
    },
    timestamp: connectP0WireTimestamp,
  );
  final peerBroadcast = WsMessage(
    type: AriamiConnectMessageType.state,
    data: <String, dynamic>{
      'activeDeviceId': 'active-device',
      'snapshot': representative.toJson(),
      'revision': 1,
    },
    timestamp: connectP0WireTimestamp,
  );
  final publicationBytes = _wireBytes(statePublication);
  final broadcastBytes = _wireBytes(peerBroadcast);

  final realisticMaximum = buildConnectP0Snapshot(
    AriamiPlaybackSnapshot.maxQueueLength,
    largeMetadata: true,
  );
  final maximumState = WsMessage(
    type: AriamiConnectMessageType.state,
    data: <String, dynamic>{
      'activate': false,
      'snapshot': realisticMaximum.toJson(),
    },
    timestamp: connectP0WireTimestamp,
  );
  final maximumPlayContext = WsMessage(
    type: AriamiConnectMessageType.command,
    data: <String, dynamic>{
      'commandId': 'controller-00000000-0000-4000-8000-000000000000',
      'command': AriamiConnectCommand.playContext,
      'arguments': <String, dynamic>{
        'snapshot': realisticMaximum.toJson(),
      },
    },
    timestamp: connectP0WireTimestamp,
  );

  return <String, dynamic>{
    'schema': 'ariami-connect-p0-measurements',
    'assumptions': <String, dynamic>{
      'protocolVersion': 2,
      'activeDevices': 1,
      'peerDevices': 2,
      'progressIntervalSeconds': 1,
      'measurementWindowSeconds': 60,
      'representativeQueueTracks': 500,
      'realisticMaximumQueueTracks': AriamiPlaybackSnapshot.maxQueueLength,
      'largeMetadataStringLengths': <String, int>{
        'id': 64,
        'title': 200,
        'artist': 160,
        'album': 200,
        'albumId': 64,
        'albumArtist': 160,
        'genre': 80,
        'filePathComponents': 180,
      },
    },
    'representative500TrackStatePublish': <String, int>{
      'messageCount': 3,
      'ownerPublicationBytes': publicationBytes,
      'eachPeerBroadcastBytes': broadcastBytes,
      'totalBytes': publicationBytes + (2 * broadcastBytes),
    },
    'representative500TrackOneMinuteAt1Hz': <String, int>{
      'messageCount': 180,
      'ownerToHubBytes': publicationBytes * 60,
      'hubToPeersBytes': broadcastBytes * 2 * 60,
      'totalBytes': (publicationBytes + 2 * broadcastBytes) * 60,
    },
    'realisticMaximum': <String, int>{
      'snapshotJsonBytes':
          utf8.encode(jsonEncode(realisticMaximum.toJson())).length,
      'statePublicationBytes': _wireBytes(maximumState),
      'playContextCommandBytes': _wireBytes(maximumPlayContext),
    },
  };
}

void main() {
  const encoder = JsonEncoder.withIndent('  ');
  // CLI output is the intended artifact of this measurement tool.
  // ignore: avoid_print
  print(encoder.convert(buildConnectP0Measurements()));
}
