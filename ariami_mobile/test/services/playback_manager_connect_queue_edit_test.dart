import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

AriamiPlaybackSnapshot _snapshot({int currentIndex = 0}) =>
    AriamiPlaybackSnapshot(
      queue: [
        {'id': 'song-a', 'title': 'A', 'artist': 'Artist'},
        {'id': 'song-b', 'title': 'B', 'artist': 'Artist'},
        {'id': 'song-c', 'title': 'C', 'artist': 'Artist'},
      ],
      currentIndex: currentIndex,
      positionMs: 1000,
      durationMs: 209000,
      isPlaying: true,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
    );

AriamiRemotePlayback _remote({int currentIndex = 0}) => AriamiRemotePlayback(
      snapshot: _snapshot(currentIndex: currentIndex),
      deviceId: 'desktop',
      deviceName: 'Ariami Desktop',
      deviceType: 'desktop',
    );

void main() {
  installSqfliteTestMocks();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('mirrored removal sends remove_queue_index and updates the mirror',
      () async {
    final manager = PlaybackManager();
    final sent = <(String, Map<String, dynamic>?)>[];
    manager.setConnectRemoteMirror(
      _remote(),
      sendCommand: (command, [arguments]) => sent.add((command, arguments)),
    );

    final removal = await manager.removeQueueItem(1);

    expect(removal, isNotNull);
    expect(removal!.wasRemote, isTrue);
    expect(removal.song.id, 'song-b');
    expect(sent.single.$1, AriamiConnectCommand.removeQueueIndex);
    expect(sent.single.$2, {'index': 1, 'id': 'song-b'});
    // The mirror reflects the edit optimistically.
    expect(manager.queue.songs.map((s) => s.id), ['song-a', 'song-c']);

    await manager.undoRemoveQueueItem(removal);

    expect(sent.last.$1, AriamiConnectCommand.insertQueueTrack);
    expect(sent.last.$2?['index'], 1);
    expect((sent.last.$2?['track'] as Map)['id'], 'song-b');
    expect(
      manager.queue.songs.map((s) => s.id),
      ['song-a', 'song-b', 'song-c'],
    );

    manager.setConnectRemoteMirror(null);
  });

  test('mirrored removal of an out-of-range index is a no-op', () async {
    final manager = PlaybackManager();
    final sent = <String>[];
    manager.setConnectRemoteMirror(
      _remote(),
      sendCommand: (command, [arguments]) => sent.add(command),
    );

    expect(await manager.removeQueueItem(7), isNull);
    expect(sent, isEmpty);

    manager.setConnectRemoteMirror(null);
  });

  test('mirrored clear removes the current song last and clears the UI',
      () async {
    final manager = PlaybackManager();
    final sent = <(String, Map<String, dynamic>?)>[];
    manager.setConnectRemoteMirror(
      _remote(currentIndex: 1),
      sendCommand: (command, [arguments]) => sent.add((command, arguments)),
    );

    await manager.clearQueue();

    expect(sent.map((command) => command.$1), [
      AriamiConnectCommand.removeQueueIndex,
      AriamiConnectCommand.removeQueueIndex,
      AriamiConnectCommand.removeQueueIndex,
    ]);
    expect(
      sent.map((command) => command.$2?['index']),
      [2, 0, 0],
    );
    expect(
      sent.map((command) => command.$2?['id']),
      ['song-c', 'song-a', 'song-b'],
    );
    expect(manager.queue, isEmpty);
    expect(manager.currentSong, isNull);
    expect(manager.isPlaying, isFalse);

    manager.setConnectRemoteMirror(null);
  });

  test('single repeated playback sends one song with repeat-all', () async {
    final manager = PlaybackManager();
    final sent = <(String, Map<String, dynamic>?)>[];
    manager.setConnectRemoteMirror(
      _remote(),
      sendCommand: (command, [arguments]) => sent.add((command, arguments)),
    );

    await manager.playSingleRepeated(
      Song(
        id: 'recent',
        title: 'Recent song',
        artist: 'Artist',
        duration: const Duration(minutes: 3),
        filePath: '/music/recent.mp3',
        fileSize: 1,
        modifiedTime: DateTime(2026),
      ),
    );

    expect(sent, hasLength(1));
    expect(sent.single.$1, AriamiConnectCommand.playContext);
    final snapshot = AriamiPlaybackSnapshot.fromJson(
      Map<String, dynamic>.from(sent.single.$2!['snapshot'] as Map),
    );
    expect(snapshot.queue.map((song) => song['id']), ['recent']);
    expect(snapshot.currentIndex, 0);
    expect(snapshot.repeatMode, 'all');
    expect(manager.queue.songs.map((song) => song.id), ['recent']);

    manager.addAllToQueue([
      Song(
        id: 'day-1',
        title: 'First',
        artist: 'Artist',
        duration: const Duration(minutes: 3),
        filePath: '/music/first.mp3',
        fileSize: 1,
        modifiedTime: DateTime(2026),
      ),
      Song(
        id: 'day-2',
        title: 'Second',
        artist: 'Artist',
        duration: const Duration(minutes: 3),
        filePath: '/music/second.mp3',
        fileSize: 1,
        modifiedTime: DateTime(2026),
      ),
    ]);

    expect(sent.map((command) => command.$1), [
      AriamiConnectCommand.playContext,
      AriamiConnectCommand.insertQueueTrack,
      AriamiConnectCommand.insertQueueTrack,
    ]);
    expect(sent[1].$2?['index'], 1);
    expect((sent[1].$2?['track'] as Map)['id'], 'day-1');
    expect(sent[2].$2?['index'], 2);
    expect((sent[2].$2?['track'] as Map)['id'], 'day-2');
    expect(
      manager.queue.songs.map((song) => song.id),
      ['recent', 'day-1', 'day-2'],
    );

    manager.setConnectRemoteMirror(null);
  });
}
