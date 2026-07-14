import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

AriamiPlaybackSnapshot _snapshot() => AriamiPlaybackSnapshot(
      queue: [
        {'id': 'song-a', 'title': 'A', 'artist': 'Artist'},
        {'id': 'song-b', 'title': 'B', 'artist': 'Artist'},
        {'id': 'song-c', 'title': 'C', 'artist': 'Artist'},
      ],
      currentIndex: 0,
      positionMs: 1000,
      durationMs: 209000,
      isPlaying: true,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
    );

AriamiRemotePlayback _remote() => AriamiRemotePlayback(
      snapshot: _snapshot(),
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
}
