import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/common/playing_bars.dart';
import 'package:ariami_mobile/widgets/library/album_grid_item.dart';
import 'package:ariami_mobile/widgets/library/album_list_item.dart';
import 'package:ariami_mobile/widgets/library/playlist_card.dart';
import 'package:ariami_mobile/widgets/library/playlist_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

final _album = AlbumModel(
  id: 'album-1',
  title: 'Playing Album',
  artist: 'Artist',
  songCount: 1,
  duration: 180,
);

final _playlist = PlaylistModel(
  id: 'local-playlist',
  name: 'Playing Playlist',
  songIds: const ['song-1'],
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026),
);

AriamiRemotePlayback _remote({
  required String sourceId,
  bool isPlaying = true,
}) {
  return AriamiRemotePlayback(
    snapshot: AriamiPlaybackSnapshot(
      queue: const [
        {'id': 'song-1', 'title': 'Song', 'artist': 'Artist'},
      ],
      currentIndex: 0,
      positionMs: 0,
      durationMs: 180000,
      isPlaying: isPlaying,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
      sourceId: sourceId,
    ),
    deviceId: 'desktop',
    deviceName: 'Ariami Desktop',
    deviceType: 'desktop',
  );
}

Future<void> _pumpRows(
  WidgetTester tester, {
  required String sourceId,
  bool isPlaying = true,
}) async {
  PlaybackManager().setConnectRemoteMirror(
    _remote(sourceId: sourceId, isPlaying: isPlaying),
    sendCommand: (_, [__]) {},
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: Scaffold(
        body: Column(
          children: [
            AlbumListItem(album: _album),
            PlaylistListItem(
              playlist: _playlist,
              sourceId: PlaybackManager.playlistSource('server-playlist'),
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  tearDown(() => PlaybackManager().setConnectRemoteMirror(null));

  testWidgets('the playing album row shows animated bars and an accent title',
      (tester) async {
    await _pumpRows(
      tester,
      sourceId: PlaybackManager.albumSource(_album.id),
    );

    final albumBars = find.descendant(
      of: find.byType(AlbumListItem),
      matching: find.byType(PlayingBars),
    );
    expect(albumBars, findsOneWidget);
    expect(tester.widget<PlayingBars>(albumBars).playing, isTrue);
    expect(
      tester.widget<Text>(find.text(_album.title)).style?.color,
      Theme.of(tester.element(find.byType(AlbumListItem))).colorScheme.primary,
    );
    expect(
      find.descendant(
        of: find.byType(PlaylistListItem),
        matching: find.byType(PlayingBars),
      ),
      findsNothing,
    );
    PlaybackManager().setConnectRemoteMirror(null);
  });

  testWidgets('a paused imported playlist keeps settled bars and accent title',
      (tester) async {
    await _pumpRows(
      tester,
      sourceId: PlaybackManager.playlistSource('server-playlist'),
      isPlaying: false,
    );

    final playlistBars = find.descendant(
      of: find.byType(PlaylistListItem),
      matching: find.byType(PlayingBars),
    );
    expect(playlistBars, findsOneWidget);
    expect(tester.widget<PlayingBars>(playlistBars).playing, isFalse);
    expect(
      tester.widget<Text>(find.text(_playlist.name)).style?.color,
      Theme.of(tester.element(find.byType(PlaylistListItem)))
          .colorScheme
          .primary,
    );
    PlaybackManager().setConnectRemoteMirror(null);
  });

  testWidgets('grid cards show the same indicator on their artwork',
      (tester) async {
    PlaybackManager().setConnectRemoteMirror(
      _remote(sourceId: PlaybackManager.albumSource(_album.id)),
      sendCommand: (_, [__]) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 180,
                height: 240,
                child: AlbumGridItem(album: _album),
              ),
              SizedBox(
                width: 180,
                height: 240,
                child: PlaylistCard(
                  playlist: _playlist,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(AlbumGridItem),
        matching: find.byType(PlayingBars),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PlaylistCard),
        matching: find.byType(PlayingBars),
      ),
      findsNothing,
    );
    PlaybackManager().setConnectRemoteMirror(null);
  });

  testWidgets('the equalizer stops repainting while the app is backgrounded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayingBars(playing: true, color: Colors.blue),
      ),
    );
    expect(tester.hasRunningAnimations, isTrue);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
}
