import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/audio/shuffle_service.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      '[four_client_capability_parity] mobile consumes the shared Connect '
      'contract fixture', () {
    final fixture = _fixture();
    final snapshot = AriamiPlaybackSnapshot.fromJson(
      Map<String, dynamic>.from(fixture['snapshot'] as Map),
    );
    final songs = snapshot.queue.map(Song.fromJson).toList(growable: false);

    expect(fixture['protocolVersion'], 2);
    expect(AriamiConnectProtocol.supportedVersions, <int>[3, 2]);
    final ownership = Map<String, dynamic>.from(fixture['ownership'] as Map);
    expect(ownership['ownerEpoch'], 7);
    expect(ownership['staleOwnerEpoch'], lessThan(ownership['ownerEpoch']));
    expect(songs.map((song) => song.id),
        <String>['track-a', 'track-b', 'track-a']);
    expect(songs[1].title, 'Second Track');
    expect(songs[0].title, isNot(songs[2].title));
    expect(snapshot.currentIndex, 1);
    expect(snapshot.shuffle, isTrue);
    expect(snapshot.repeatMode, 'all');
    expect(snapshot.volume, 0.75);

    final playContext =
        Map<String, dynamic>.from(fixture['playContext'] as Map);
    expect(playContext['type'], AriamiConnectMessageType.command);
    final playData = Map<String, dynamic>.from(playContext['data'] as Map);
    expect(playData['command'], AriamiConnectCommand.playContext);
    expect(playData['ownerEpoch'], ownership['ownerEpoch']);
    final arguments = Map<String, dynamic>.from(playData['arguments'] as Map);
    final playSnapshot = AriamiPlaybackSnapshot.fromJson(
      Map<String, dynamic>.from(arguments['snapshot'] as Map),
    );
    expect(playSnapshot.queue.map((track) => track['id']),
        <String>['track-a', 'track-b', 'track-a']);
    expect(playSnapshot.shuffle, isTrue);
    expect(playSnapshot.repeatMode, 'all');

    final baseline = Map<String, dynamic>.from(
      (fixture['clientBaselines'] as Map)['mobile'] as Map,
    );
    expect(
      baseline['supportsClearQueue'],
      AriamiConnectCommand.supported.contains(AriamiConnectCommand.clearQueue),
    );
    expect(baseline['supportsOwnerEpochFencing'], isTrue);
    expect(
      Set<String>.from(baseline['supportedCommands'] as List),
      PlaybackManager.connectSupportedCommands,
    );
    expect(PlaybackManager.connectSupportedCommands,
        isNot(contains(AriamiConnectCommand.setVolume)));
    _expectBackingOrder(fixture);
  });
}

Map<String, dynamic> _fixture() {
  final file = File(
      '${Directory.current.parent.path}/ariami_core/test/fixtures/connect/v2_contract.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Drives the shared `connect_queue` fixture through this client's real
/// decoder and shuffle service. Re-indexing the fixture's own arrays would
/// pass even if the client ignored `backingOrder` entirely.
void _expectBackingOrder(Map<String, dynamic> fixture) {
  final snapshot = _snapshotFromV3Queue(fixture);
  expect(snapshot.backingOrder, <int>[2, 0, 1]);
  expect(snapshot.sourceId, 'playlist:shared-fixture');

  final resolved = snapshot.queue.map(Song.fromJson).toList(growable: false);
  final service = ShuffleService<Song>()
    ..restoreShuffled(
      originalQueue:
          snapshot.backingOrder.map((index) => resolved[index]).toList(),
      shuffledQueue: resolved,
    );

  expect(service.backingOrderFor(resolved), <int>[2, 0, 1]);
  expect(
    service.disableShuffle(resolved.first).map((song) => song.title),
    <String>['First Track (Encore)', 'First Track', 'Second Track'],
    reason: 'duplicate IDs must not collapse onto one occurrence',
  );
}

/// Rebuilds the wire snapshot a v3 peer would hold after `connect_queue`,
/// using the shared fixture's own bytes.
AriamiPlaybackSnapshot _snapshotFromV3Queue(Map<String, dynamic> fixture) {
  final data =
      Map<String, dynamic>.from((fixture['v3Queue'] as Map)['data'] as Map);
  return AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
    'queue': data['tracks'],
    'backingOrder': data['backingOrder'],
    'sourceId': data['sourceId'],
    'currentIndex': 0,
    'positionMs': 0,
    'durationMs': 0,
    'isPlaying': false,
    'shuffle': true,
    'repeatMode': 'off',
    'volume': 1.0,
  });
}
