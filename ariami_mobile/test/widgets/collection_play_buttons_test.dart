import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/services/audio/play_buttons_follow_playback_service.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:ariami_mobile/widgets/collection_play_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

const _source = 'playlist:p1';

/// A mirrored Connect device stands in for a live queue: it puts the manager
/// into a "this collection is playing" state, and turns every button press
/// into an observable command, without needing an audio engine or a server.
AriamiRemotePlayback _remote({
  required String sourceId,
  bool isPlaying = true,
  bool shuffle = false,
}) =>
    AriamiRemotePlayback(
      snapshot: AriamiPlaybackSnapshot(
        queue: const <Map<String, dynamic>>[
          {'id': 's1', 'title': 'One', 'artist': 'Artist'},
        ],
        currentIndex: 0,
        positionMs: 0,
        durationMs: 1000,
        isPlaying: isPlaying,
        shuffle: shuffle,
        repeatMode: 'off',
        volume: 1,
        sourceId: sourceId,
      ),
      deviceId: 'desk',
      deviceName: 'Ariami Desktop',
      deviceType: 'desktop',
    );

/// Drops the mirror so its one-second progress ticker stops before the test
/// ends; a pending timer fails the test even when every expectation passed.
void _stopMirror() => PlaybackManager().setConnectRemoteMirror(null);

void main() {
  installSqfliteTestMocks();

  final commands = <String>[];
  var started = 0;
  var shuffled = 0;

  Future<void> pump(
    WidgetTester tester, {
    required bool follow,
    required String playingSource,
    bool isPlaying = true,
    bool shuffle = false,
  }) async {
    final playback = PlaybackManager();
    await PlayButtonsFollowPlaybackService().setEnabled(follow);
    playback.setConnectRemoteMirror(
      _remote(sourceId: playingSource, isPlaying: isPlaying, shuffle: shuffle),
      sendCommand: (command, [_]) => commands.add(command),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              CollectionPlayButton(
                sourceId: _source,
                onPlay: () => started++,
              ),
              CollectionShuffleButton(
                sourceId: _source,
                onShuffle: () => shuffled++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // The service reads the app's pre-loaded prefs cache synchronously.
    await initializeSharedPrefs();
    PlayButtonsFollowPlaybackService().resetForTesting();
    commands.clear();
    started = 0;
    shuffled = 0;
  });

  testWidgets('off: the buttons always restart the collection', (tester) async {
    await pump(tester, follow: false, playingSource: _source, shuffle: true);

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byKey(shuffleOnDotKey), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect((started, shuffled), (1, 1));
    expect(commands, isEmpty);
    _stopMirror();
  });

  testWidgets('on: the playing collection pauses and toggles its queue',
      (tester) async {
    await pump(tester, follow: true, playingSource: _source, shuffle: true);

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byKey(shuffleOnDotKey), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect((started, shuffled), (0, 0));
    expect(commands, <String>[
      AriamiConnectCommand.toggle,
      AriamiConnectCommand.toggleShuffle,
    ]);
    _stopMirror();
  });

  testWidgets('on: another collection keeps plain Play and Shuffle',
      (tester) async {
    await pump(
      tester,
      follow: true,
      playingSource: 'playlist:other',
      shuffle: true,
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byKey(shuffleOnDotKey), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect((started, shuffled), (1, 1));
    _stopMirror();
  });
}
