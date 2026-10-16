import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/common/playing_bars.dart';
import 'package:ariami_mobile/widgets/search/search_result_song_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

final _song = SongModel(
  id: 'song-1',
  title: 'Billie Jean',
  artist: 'Michael Jackson',
  duration: 294,
);

final _otherSong = SongModel(
  id: 'song-2',
  title: 'Beat It',
  artist: 'Michael Jackson',
  duration: 258,
);

AriamiRemotePlayback _remote({
  required String songId,
  bool isPlaying = true,
}) {
  return AriamiRemotePlayback(
    snapshot: AriamiPlaybackSnapshot(
      queue: [
        {'id': songId, 'title': 'Test Title', 'artist': 'Test Artist'},
      ],
      currentIndex: 0,
      positionMs: 0,
      durationMs: 180000,
      isPlaying: isPlaying,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
      sourceId: 'test-source',
    ),
    deviceId: 'desktop',
    deviceName: 'Ariami Desktop',
    deviceType: 'desktop',
  );
}

void main() {
  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  tearDown(() => PlaybackManager().setConnectRemoteMirror(null));

  testWidgets(
    'shows primary color title and animated PlayingBars when song is playing',
    (tester) async {
      PlaybackManager().setConnectRemoteMirror(
        _remote(songId: _song.id, isPlaying: true),
        sendCommand: (_, [__]) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
          home: Scaffold(
            body: SearchResultSongItem(
              song: _song,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final barsFinder = find.byType(PlayingBars);
      expect(barsFinder, findsOneWidget);
      expect(tester.widget<PlayingBars>(barsFinder).playing, isTrue);

      final titleText = tester.widget<Text>(find.text('Billie Jean'));
      expect(
        titleText.style?.color,
        Theme.of(tester.element(find.byType(SearchResultSongItem)))
            .colorScheme
            .primary,
      );

      PlaybackManager().setConnectRemoteMirror(null);
    },
  );

  testWidgets(
    'shows settled PlayingBars when song is current but playback is paused',
    (tester) async {
      PlaybackManager().setConnectRemoteMirror(
        _remote(songId: _song.id, isPlaying: false),
        sendCommand: (_, [__]) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
          home: Scaffold(
            body: SearchResultSongItem(
              song: _song,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final barsFinder = find.byType(PlayingBars);
      expect(barsFinder, findsOneWidget);
      expect(tester.widget<PlayingBars>(barsFinder).playing, isFalse);

      final titleText = tester.widget<Text>(find.text('Billie Jean'));
      expect(
        titleText.style?.color,
        Theme.of(tester.element(find.byType(SearchResultSongItem)))
            .colorScheme
            .primary,
      );

      PlaybackManager().setConnectRemoteMirror(null);
    },
  );

  testWidgets(
    'does not show PlayingBars or primary color title for non-playing song',
    (tester) async {
      PlaybackManager().setConnectRemoteMirror(
        _remote(songId: _otherSong.id, isPlaying: true),
        sendCommand: (_, [__]) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
          home: Scaffold(
            body: SearchResultSongItem(
              song: _song,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PlayingBars), findsNothing);

      final titleText = tester.widget<Text>(find.text('Billie Jean'));
      expect(
        titleText.style?.color,
        isNot(
          Theme.of(tester.element(find.byType(SearchResultSongItem)))
              .colorScheme
              .primary,
        ),
      );

      PlaybackManager().setConnectRemoteMirror(null);
    },
  );

  testWidgets(
    'renders isInRecentSearch history badge on top-right of artwork',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultSongItem(
              song: _song,
              onTap: () {},
              isInRecentSearch: true,
              isDownloaded: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
      expect(find.byIcon(Icons.download_done), findsOneWidget);

      final historyPositioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byIcon(Icons.history_rounded),
          matching: find.byType(Positioned),
        ),
      );
      expect(historyPositioned.top, 0);
      expect(historyPositioned.right, 0);

      final downloadPositioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byIcon(Icons.download_done),
          matching: find.byType(Positioned),
        ),
      );
      expect(downloadPositioned.bottom, 0);
      expect(downloadPositioned.right, 0);
    },
  );

  testWidgets(
    'does not render history badge when isInRecentSearch is false',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultSongItem(
              song: _song,
              onTap: () {},
              isInRecentSearch: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.history_rounded), findsNothing);
    },
  );
}
