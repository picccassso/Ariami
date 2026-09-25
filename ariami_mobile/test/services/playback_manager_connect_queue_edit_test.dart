import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/models/playback_queue.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/audio/keep_queue_on_tap_service.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
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

Song _song(String id) => Song(
      id: id,
      title: id,
      artist: 'Artist',
      duration: const Duration(minutes: 3),
      filePath: '/music/$id.mp3',
      fileSize: 1,
      modifiedTime: DateTime(2026),
    );

void main() {
  installSqfliteTestMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await initializeSharedPrefs();
  });

  test('PlaybackQueue owns a growable copy of every input list', () {
    final fixedInput = List<Song>.unmodifiable(<Song>[_song('song-a')]);
    final queue = PlaybackQueue(songs: fixedInput);

    queue.addSong(_song('song-c'));
    queue.insertSong(1, _song('song-b'));

    expect(queue.songs.map((song) => song.id), [
      'song-a',
      'song-b',
      'song-c',
    ]);

    final mutableInput = <Song>[_song('owned')];
    final ownedQueue = PlaybackQueue(songs: mutableInput);
    mutableInput.clear();
    expect(ownedQueue.songs.map((song) => song.id), ['owned']);
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

  test('mirrored clear keeps Now Playing and removes every other item',
      () async {
    final manager = PlaybackManager();
    final sent = <(String, Map<String, dynamic>?)>[];
    manager.setConnectRemoteMirror(
      _remote(currentIndex: 1),
      sendCommand: (command, [arguments]) => sent.add((command, arguments)),
    );

    await manager.clearQueue();

    expect(sent, hasLength(1));
    expect(sent.single.$1, AriamiConnectCommand.clearQueue);
    expect(sent.single.$2, isNull);
    expect(manager.queue.songs.map((song) => song.id), ['song-b']);
    expect(manager.currentSong?.id, 'song-b');
    expect(manager.isPlaying, isTrue);

    manager.setConnectRemoteMirror(null);
  });

  test('Connect play drops a stale mirror before targeting the local engine',
      () async {
    final manager = PlaybackManager();
    final sent = <String>[];
    manager.setConnectRemoteMirror(
      _remote(),
      sendCommand: (command, [arguments]) => sent.add(command),
    );

    await manager.handleConnectCommand(AriamiConnectCommand.play, const {});

    expect(manager.isConnectRemoteActive, isFalse);
    expect(sent, isEmpty);
  });

  test('unchanged mirrored queue keeps its Song instances across broadcasts',
      () {
    final manager = PlaybackManager();
    manager.setConnectRemoteMirror(_remote());
    final before = manager.queue.songs;

    // A position-tick broadcast: same queue and index, newer position.
    manager.setConnectRemoteMirror(AriamiRemotePlayback(
      snapshot: _snapshot().copyWith(positionMs: 2000),
      deviceId: 'desktop',
      deviceName: 'Ariami Desktop',
      deviceType: 'desktop',
    ));

    final after = manager.queue.songs;
    expect(after, hasLength(before.length));
    for (var i = 0; i < after.length; i++) {
      // Identity, not equality: queue rows are keyed by object identity, and
      // fresh instances per broadcast would recreate every row's artwork.
      expect(identical(before[i], after[i]), isTrue);
    }

    // A track advance keeps the songs but must move the queue's index.
    manager.setConnectRemoteMirror(_remote(currentIndex: 1));
    expect(manager.queue.currentIndex, 1);
    expect(identical(manager.queue.songs.first, before.first), isTrue);

    // A genuinely different queue rebuilds the mirrored songs.
    manager.setConnectRemoteMirror(AriamiRemotePlayback(
      snapshot: AriamiPlaybackSnapshot(
        queue: [
          {'id': 'song-a', 'title': 'A', 'artist': 'Artist'},
          {'id': 'song-d', 'title': 'D', 'artist': 'Artist'},
        ],
        currentIndex: 0,
        positionMs: 1000,
        durationMs: 209000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
      ),
      deviceId: 'desktop',
      deviceName: 'Ariami Desktop',
      deviceType: 'desktop',
    ));
    expect(manager.queue.songs.map((song) => song.id), ['song-a', 'song-d']);

    manager.setConnectRemoteMirror(null);
  });

  test('local clear keeps Now Playing and removes every other item', () async {
    final manager = PlaybackManager();
    manager.setConnectRemoteMirror(null);
    await manager.stopAndClearQueue();
    manager.addAllToQueue([_song('song-a'), _song('song-b'), _song('song-c')]);

    await manager.clearQueue();

    expect(manager.queue.songs.map((song) => song.id), ['song-a']);
    expect(manager.currentSong?.id, 'song-a');

    await manager.stopAndClearQueue();
  });

  test(
      '[prepared_target_restored] empty pre-prepare state clears a prepared '
      'Connect queue', () async {
    final manager = PlaybackManager();
    manager.setConnectRemoteMirror(null);
    await manager.stopAndClearQueue();
    manager.addAllToQueue([_song('prepared-remote')]);
    expect(manager.queue.songs, isNotEmpty);

    final local = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
      'shuffle': true,
      'repeatMode': 'one',
    });
    await manager.applyConnectSnapshot(local);

    expect(manager.queue.songs, isEmpty);
    expect(manager.connectSnapshot.shuffle, local.shuffle);
    expect(manager.connectSnapshot.repeatMode, local.repeatMode);
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

  test('[play_context_backing_order] shuffled remote play retains source order',
      () async {
    final manager = PlaybackManager();
    final sent = <(String, Map<String, dynamic>?)>[];
    manager.setConnectRemoteMirror(
      _remote(),
      sendCommand: (command, [arguments]) => sent.add((command, arguments)),
    );
    final songs = <Song>[
      Song(
        id: 'a',
        title: 'A',
        artist: 'Artist',
        duration: const Duration(minutes: 1),
        filePath: '/a',
        fileSize: 1,
        modifiedTime: DateTime(2026),
      ),
      Song(
        id: 'b',
        title: 'B',
        artist: 'Artist',
        duration: const Duration(minutes: 1),
        filePath: '/b',
        fileSize: 1,
        modifiedTime: DateTime(2026),
      ),
      Song(
        id: 'c',
        title: 'C',
        artist: 'Artist',
        duration: const Duration(minutes: 1),
        filePath: '/c',
        fileSize: 1,
        modifiedTime: DateTime(2026),
      ),
    ];

    await manager.playShuffled(songs);
    final snapshot = AriamiPlaybackSnapshot.fromJson(
      Map<String, dynamic>.from(sent.single.$2!['snapshot'] as Map),
    );
    expect(snapshot.shuffle, isTrue);
    expect(
      snapshot.backingOrder.map((index) => snapshot.queue[index]['id']),
      <String>['a', 'b', 'c'],
    );
    manager.setConnectRemoteMirror(null);
  });

  group('queue replacement undo', () {
    Future<List<Future<void> Function()>> undosDuring(
      PlaybackManager manager,
      Future<void> Function() action,
    ) async {
      final undos = <Future<void> Function()>[];
      final subscription = manager.queueReplacedStream.listen(undos.add);
      await action();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      return undos;
    }

    test('mirrored Play offers undo that restores the previous context',
        () async {
      final manager = PlaybackManager();
      final sent = <(String, Map<String, dynamic>?)>[];
      manager.setConnectRemoteMirror(
        _remote(),
        sendCommand: (command, [arguments]) => sent.add((command, arguments)),
      );

      final undos = await undosDuring(
        manager,
        () => manager.playSongs([_song('new')]),
      );
      expect(undos, hasLength(1));
      expect(manager.queue.songs.map((s) => s.id), ['new']);

      await undos.single();

      expect(sent.last.$1, AriamiConnectCommand.playContext);
      final restored = AriamiPlaybackSnapshot.fromJson(
        Map<String, dynamic>.from(sent.last.$2!['snapshot'] as Map),
      );
      expect(
          restored.queue.map((t) => t['id']), ['song-a', 'song-b', 'song-c']);
      expect(restored.currentIndex, 0);
      expect(restored.positionMs, greaterThanOrEqualTo(1000));
      expect(restored.isPlaying, isTrue);
      expect(
        manager.queue.songs.map((s) => s.id),
        ['song-a', 'song-b', 'song-c'],
      );

      manager.setConnectRemoteMirror(null);
    });

    test('no undo when nothing was lined up after the current song', () async {
      final manager = PlaybackManager();
      manager.setConnectRemoteMirror(
        _remote(currentIndex: 2),
        sendCommand: (command, [arguments]) {},
      );

      final undos = await undosDuring(
        manager,
        () => manager.playSongs([_song('new')]),
      );
      expect(undos, isEmpty);

      manager.setConnectRemoteMirror(null);
    });

    test('no undo when hopping within the context already playing', () async {
      final manager = PlaybackManager();
      manager.setConnectRemoteMirror(
        _remote(),
        sendCommand: (command, [arguments]) {},
      );

      final undos = await undosDuring(
        manager,
        () => manager.playSongs(
          [_song('song-a'), _song('song-b'), _song('song-c')],
          startIndex: 1,
        ),
      );
      expect(undos, isEmpty);

      manager.setConnectRemoteMirror(null);
    });

    test('local Play offers undo that restores hand-queued songs', () async {
      final manager = PlaybackManager();
      manager.setConnectRemoteMirror(null);
      await manager.stopAndClearQueue();
      manager.addAllToQueue([_song('song-a'), _song('song-b')]);

      final undos = await undosDuring(
        manager,
        () => manager.playSongs([_song('new')]).catchError((_) {}),
      );
      expect(undos, hasLength(1));

      await undos.single();

      expect(manager.queue.songs.map((s) => s.id), ['song-a', 'song-b']);
      expect(manager.currentSong?.id, 'song-a');

      await manager.stopAndClearQueue();
    });

    group('with Keep My Queue When Tapping a Song on', () {
      setUp(() => KeepQueueOnTapService().setEnabled(true));
      tearDown(() => KeepQueueOnTapService().setEnabled(false));

      test('a tapped song plays now and the local queue carries on after it',
          () async {
        final manager = PlaybackManager();
        manager.setConnectRemoteMirror(null);
        await manager.stopAndClearQueue();
        manager.addAllToQueue([_song('song-a'), _song('song-b')]);

        final undos = await undosDuring(
          manager,
          () => manager.playTappedSong([_song('new'), _song('new-2')],
              index: 0).catchError((_) {}),
        );

        expect(undos, isEmpty);
        expect(
          manager.queue.songs.map((s) => s.id),
          ['new', 'song-a', 'song-b'],
        );
        expect(manager.currentSong?.id, 'new');

        await manager.stopAndClearQueue();
      });

      test('a tapped song is inserted into the mirrored queue', () async {
        final manager = PlaybackManager();
        // Clears the takeover hold left by local playback in earlier tests.
        manager.setConnectRemoteMirror(null);
        final sent = <(String, Map<String, dynamic>?)>[];
        manager.setConnectRemoteMirror(
          _remote(currentIndex: 1),
          sendCommand: (command, [arguments]) => sent.add((command, arguments)),
        );

        await manager.playTappedSong([_song('new'), _song('new-2')], index: 0);

        final snapshot = AriamiPlaybackSnapshot.fromJson(
          Map<String, dynamic>.from(sent.single.$2!['snapshot'] as Map),
        );
        expect(
          snapshot.queue.map((t) => t['id']),
          ['song-a', 'new', 'song-b', 'song-c'],
        );
        expect(snapshot.currentIndex, 1);
        expect(snapshot.backingOrder, [0, 1, 2, 3]);

        manager.setConnectRemoteMirror(null);
      });

      test('Play still replaces the queue and offers undo', () async {
        final manager = PlaybackManager();
        // Clears the takeover hold left by local playback in earlier tests.
        manager.setConnectRemoteMirror(null);
        manager.setConnectRemoteMirror(
          _remote(),
          sendCommand: (command, [arguments]) {},
        );

        final undos = await undosDuring(
          manager,
          () => manager.playSongs([_song('new'), _song('new-2')]),
        );

        expect(undos, hasLength(1));
        expect(manager.queue.songs.map((s) => s.id), ['new', 'new-2']);

        manager.setConnectRemoteMirror(null);
      });
    });
  });
}
