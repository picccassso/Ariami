import 'dart:async';
import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/main.dart' as app;
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/audio/audio_handler.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

void main() {
  installSqfliteTestMocks();
  final player = _Player();
  final manager = PlaybackManager();
  late AriamiAudioHandler handler;
  late Directory docs;
  final songs = List.generate(
      12,
      (i) => Song(
            id: 'song-$i',
            title: 'Song $i',
            artist: 'Artist',
            duration: const Duration(minutes: 3),
            filePath: '/tmp/song-$i.mp3',
            fileSize: 1,
            modifiedTime: DateTime(2026),
          ));
  AriamiPlaybackSnapshot snapshot({int currentIndex = 9}) =>
      AriamiPlaybackSnapshot(
        queue: songs.map((s) => s.toJson()).toList(),
        currentIndex: currentIndex,
        positionMs: 12000,
        durationMs: 180000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'all',
        volume: 0.5,
      );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    docs = await Directory.systemTemp.createTemp('ariami_completion_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'plugins.flutter.io/path_provider',
      'dev.fluttercommunity.plus/connectivity',
      'com.yosemiteyss.flutter_volume_controller/method',
      'com.yosemiteyss.flutter_volume_controller/event'
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'check') return ['none'];
        if (call.method == 'getExternalCacheDirectories' ||
            call.method == 'getExternalStorageDirectories') {
          return [docs.path];
        }
        if (name.contains('path_provider')) return docs.path;
        return null;
      });
    }
    handler = AriamiAudioHandler(player: player);
    app.audioHandler = handler;
    manager.initialize();
    await _pump();
  });
  setUp(() async {
    manager.setConnectRemoteMirror(null);
    try {
      // Queue adoption succeeds; no real server is attached to start streaming.
      await manager.applyConnectSnapshot(snapshot());
    } on Exception {
      // Player events below exercise the already-adopted queue.
    }
    await handler.loadSong(songs[9], 'file:///tmp/song-9.mp3');
    await _pump();
  });
  tearDown(() => manager.setConnectRemoteMirror(null));
  tearDownAll(() async {
    manager.dispose();
    await handler.dispose();
    app.audioHandler = null;
    await player.states.close();
    await player.indices.close();
    await docs.delete(recursive: true);
  });

  test('paused completion leaves track ten and repeat-all unchanged', () async {
    player.emit(true, ProcessingState.ready);
    await _pump();
    player.emit(false, ProcessingState.completed);
    await _pump();
    expect(manager.queue.currentIndex, 9);
    expect(manager.localCurrentSong?.id, 'song-9');
    expect(manager.connectSnapshot.repeatMode, 'all');
  });

  test('stale local completions cannot advance the desktop mirror', () async {
    final sent = <String>[];
    manager.setConnectRemoteMirror(
        AriamiRemotePlayback(
          snapshot: snapshot(),
          deviceId: 'desktop',
          deviceName: 'Desktop',
          deviceType: 'desktop',
        ),
        sendCommand: (command, [args]) => sent.add(command));
    for (var i = 0; i < 14; i++) {
      player.emit(true, ProcessingState.ready);
      player.emit(true, ProcessingState.completed);
      await _pump();
    }
    expect(manager.currentSong?.id, 'song-9');
    expect(manager.localCurrentSong?.id, 'song-9');
    expect(manager.queue.currentIndex, 9);
    expect(sent, isEmpty);
  });

  test('genuine repeat-all completion wraps the last track once', () async {
    try {
      await manager.applyConnectSnapshot(snapshot(currentIndex: 11));
    } on Exception {
      // No server is attached; the queue and repeat mode were already adopted.
    }
    await handler.loadSong(songs[11], 'file:///tmp/song-11.mp3');
    player.emit(true, ProcessingState.ready);
    await _pump();
    player.emit(true, ProcessingState.completed);
    await _pump();
    expect(manager.localCurrentSong?.id, 'song-0');
    expect(manager.connectSnapshot.repeatMode, 'all');
    player.emit(false, ProcessingState.completed);
    await _pump();
    expect(manager.localCurrentSong?.id, 'song-0');
  });

  test('a stale native gapless index cannot overwrite mirrored metadata',
      () async {
    await handler.loadSong(songs[9], 'file:///tmp/song-9.mp3',
        upcoming: GaplessPlaybackItem(
            song: songs[10], streamUrl: 'file:///tmp/song-10.mp3'));
    manager.setConnectRemoteMirror(
        AriamiRemotePlayback(
          snapshot: snapshot(),
          deviceId: 'desktop',
          deviceName: 'Desktop',
          deviceType: 'desktop',
        ),
        sendCommand: (_, [args]) {});
    player.indices.add(1);
    await _pump();
    expect(handler.mediaItem.value?.id, 'song-9');
    expect(manager.currentSong?.id, 'song-9');
    expect(manager.localCurrentSong?.id, 'song-9');
  });

  test('handoff cancels a completion awaiting the skip delay', () async {
    player.emit(true, ProcessingState.ready);
    await _pump();
    player.emit(true, ProcessingState.completed);
    await _pump();
    expect(manager.localCurrentSong?.id, 'song-10');
    final plays = player.plays;
    await manager.pauseLocal();
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(player.plays, plays);
    expect(manager.localCurrentSong?.id, 'song-10');
  });

  test('pausing a completed engine cannot launch a second advance', () async {
    player.emit(true, ProcessingState.ready);
    await _pump();
    player.emit(true, ProcessingState.completed);
    await _pump();
    player.emit(false, ProcessingState.completed);
    player.emit(true, ProcessingState.completed);
    await _pump();
    expect(manager.localCurrentSong?.id, 'song-10');
    await manager.pauseLocal();
    await Future<void>.delayed(const Duration(milliseconds: 750));
  });

  test('internal seek and resume never become commands to the desktop',
      () async {
    final sent = <String>[];
    manager.setConnectRemoteMirror(
        AriamiRemotePlayback(
          snapshot: snapshot(),
          deviceId: 'desktop',
          deviceName: 'Desktop',
          deviceType: 'desktop',
        ),
        sendCommand: (command, [args]) => sent.add(command));
    await handler.seekLocal(const Duration(seconds: 20));
    await handler.playLocal();
    await _pump();
    expect(sent, isEmpty);
    await manager.pauseLocal();
  });

  test('the audio handler cannot autoplay a load finished after handoff',
      () async {
    player.loadGate = Completer<void>();
    final plays = player.plays;
    final load = handler.playSong(songs[9], 'file:///tmp/song-9.mp3');
    await _pump();
    await manager.pauseLocal();
    player.loadGate!.complete();
    await load;
    player.loadGate = null;
    expect(player.plays, plays);
  });
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _Player implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast();
  final indices = StreamController<int?>.broadcast();
  Completer<void>? loadGate;
  int plays = 0;
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  void emit(bool isPlaying, ProcessingState state) {
    playing = isPlaying;
    processingState = state;
    states.add(PlayerState(isPlaying, state));
  }

  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  int? get currentIndex => 0;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  double get speed => 1;
  @override
  PlaybackEvent get playbackEvent => PlaybackEvent();
  @override
  Future<Duration?> setAudioSources(List<AudioSource> sources,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition,
      ShuffleOrder? shuffleOrder}) async {
    await loadGate?.future;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    plays++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
