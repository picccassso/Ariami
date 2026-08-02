import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

/// Mobile identifies songs by ID everywhere else, so the Connect boundary is
/// where duplicate occurrences are most likely to collapse onto one copy.
/// These cover the positional round trip the wire actually carries.
AriamiPlaybackSnapshot _duplicateSnapshot({
  required bool shuffle,
  List<int>? backingOrder,
  int currentIndex = 0,
}) =>
    AriamiPlaybackSnapshot(
      queue: const <Map<String, dynamic>>[
        {'id': 'song-c', 'title': 'C', 'artist': 'Artist'},
        {'id': 'duplicate', 'title': 'First A', 'artist': 'Artist'},
        {'id': 'duplicate', 'title': 'Second A', 'artist': 'Artist'},
      ],
      backingOrder: backingOrder,
      currentIndex: currentIndex,
      positionMs: 0,
      durationMs: 0,
      isPlaying: false,
      shuffle: shuffle,
      repeatMode: 'off',
      volume: 1,
    );

/// [PlaybackManager.applyConnectSnapshot] adopts the queue, shuffle service
/// and repeat mode before it asks the streaming layer to start the track.
/// That last step needs a server connection these tests deliberately do not
/// have; the Connect boundary covered here has already been crossed by then,
/// and a failure any earlier still shows up as a failed expectation below.
Future<void> _adopt(
    PlaybackManager manager, AriamiPlaybackSnapshot snapshot) async {
  try {
    await manager.applyConnectSnapshot(snapshot);
  } on Exception {
    // Starting playback is out of scope for the snapshot contract.
  }
}

void main() {
  installSqfliteTestMocks();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  late Directory docsDir;

  setUpAll(() async {
    docsDir = await Directory.systemTemp.createTemp('ariami_connect_snapshot_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getExternalCacheDirectories':
        case 'getExternalStorageDirectories':
          return <String>[docsDir.path];
        default:
          return docsDir.path;
      }
    });
    messenger.setMockMethodCallHandler(connectivityChannel, (call) async {
      return call.method == 'check' ? <String>['none'] : null;
    });
  });

  tearDownAll(() async {
    if (docsDir.existsSync()) await docsDir.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('a shuffled handoff round trips resolved and backing order', () async {
    final first = PlaybackManager();
    await _adopt(
      first,
      _duplicateSnapshot(shuffle: true, backingOrder: <int>[1, 2, 0]),
    );

    final handedOff = first.connectSnapshot;
    expect(
      handedOff.queue.map((track) => track['title']),
      <String>['C', 'First A', 'Second A'],
      reason: 'the wire carries resolved play order',
    );
    expect(handedOff.backingOrder, <int>[1, 2, 0]);

    // A second handoff must preserve both meanings, not just the first.
    final second = PlaybackManager();
    await _adopt(second, handedOff);
    expect(
      second.connectSnapshot.queue.map((track) => track['title']),
      <String>['C', 'First A', 'Second A'],
    );
    expect(second.connectSnapshot.backingOrder, <int>[1, 2, 0]);
  });

  test('disabling shuffle after a handoff restores the backing order',
      () async {
    final manager = PlaybackManager();
    await _adopt(
      manager,
      _duplicateSnapshot(shuffle: true, backingOrder: <int>[1, 2, 0]),
    );

    manager.toggleShuffle();

    expect(
      manager.queue.songs.map((song) => song.title),
      <String>['First A', 'Second A', 'C'],
      reason: 'the pre-shuffle order was carried positionally, not by ID',
    );
    expect(manager.currentSong?.title, 'C',
        reason: 'toggling shuffle keeps the current track stable');
    expect(manager.connectSnapshot.backingOrder, <int>[0, 1, 2]);
  });

  test('an unshuffled v2 handoff keeps identity backing order', () async {
    final manager = PlaybackManager();
    await _adopt(manager, _duplicateSnapshot(shuffle: false));

    final snapshot = manager.connectSnapshot;
    expect(snapshot.backingOrder, <int>[0, 1, 2]);
    expect(
      snapshot.queue.map((track) => track['title']),
      <String>['C', 'First A', 'Second A'],
    );
  });
}
