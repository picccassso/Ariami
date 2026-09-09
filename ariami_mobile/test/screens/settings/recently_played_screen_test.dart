import 'dart:io';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/common/queue_action_confirmation.dart';

import 'package:ariami_mobile/models/song_stats.dart';
import 'package:ariami_mobile/screens/album_detail_screen.dart';
import 'package:ariami_mobile/screens/settings/recently_played_screen.dart';
import 'package:ariami_mobile/services/playlist_service.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:ariami_mobile/widgets/common/mini_player_aware_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/private_sqflite_ffi.dart';

SongStats _play(String id, String title, DateTime at) => SongStats(
      songId: id,
      playCount: 1,
      totalTime: const Duration(minutes: 3),
      firstPlayed: at,
      lastPlayed: at,
      songTitle: title,
      songArtist: 'Artist',
    );

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForCatalog(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byTooltip('Add to queue').evaluate().isNotEmpty) break;
    }
  });
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    // Private database and storage: `flutter test` runs files concurrently
    // and the shared FFI directory is not safe to reset from here.
    tempDir = await initPrivateSqfliteFfi('ariami_recently_played_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
    await StreamingStatsService().initialize();
    final db = await LibrarySyncDatabase.create();
    await db.upsertAlbums(const [
      LibraryAlbumRow(
        id: 'history-album',
        title: 'History Album',
        artist: 'Artist',
        songCount: 1,
        duration: 180,
      ),
    ]);
    await db.upsertSongs(const [
      LibrarySongRow(
        id: 'history',
        title: 'History Song',
        artist: 'Artist',
        albumId: 'history-album',
        duration: 180,
      ),
      LibrarySongRow(
        id: 'no-album-song',
        title: 'No Album Song',
        artist: 'Artist',
        duration: 180,
      ),
      LibrarySongRow(
        id: 'stale-album-song',
        title: 'Stale Album Song',
        artist: 'Artist',
        albumId: 'deleted-album-id',
        duration: 180,
      ),
    ]);
    await db.saveSyncState(const LibrarySyncState(
      lastAppliedToken: 1,
      bootstrapComplete: true,
      lastSyncEpochMs: 1,
    ));
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  testWidgets('the last week opens, older days wait and carry a past year',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    // The account overlay is the display source; no server is needed for it.
    StreamingStatsService().setAccountStatsOverlay([
      _play('song-today', 'Today Song', today),
      _play(
          'song-recent',
          'Recent Song',
          today.subtract(
            const Duration(days: 3),
          )),
      _play(
          'song-month',
          'Last Month Song',
          today.subtract(
            const Duration(days: 25),
          )),
      _play('song-old', 'Old Song', DateTime(2019, 7, 20, 12)),
    ]);
    addTearDown(() => StreamingStatsService().setAccountStatsOverlay(null));

    await tester.pumpWidget(
      const MaterialApp(home: RecentlyPlayedScreen()),
    );
    // Artwork placeholders spin forever offline, so settle by hand.
    await _pumpFrames(tester);

    // Within the last week: open on arrival.
    expect(find.text('Today Song'), findsOneWidget);
    expect(find.text('Recent Song'), findsOneWidget);
    // Older: the day is listed, its tracks are not built until asked for.
    expect(find.text('Last Month Song'), findsNothing);
    expect(find.text('Old Song'), findsNothing);

    // Past years are spelled out; the current year never is.
    expect(find.textContaining(', 2019'), findsOneWidget);
    expect(find.textContaining(', ${now.year}'), findsNothing);

    await tester.tap(find.textContaining(', 2019'));
    await _pumpFrames(tester);

    expect(find.text('Old Song'), findsOneWidget);
    // Opening one old day leaves the others alone.
    expect(find.text('Last Month Song'), findsNothing);
  });

  testWidgets(
      'history queues individual tracks without replacing Connect playback',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
      _play('missing', 'Missing Song', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    final commands = <(String, Map<String, dynamic>?)>[];
    playback.setConnectRemoteMirror(
        AriamiRemotePlayback(
          snapshot: AriamiPlaybackSnapshot(
            queue: [
              {'id': 'current', 'title': 'Current', 'artist': 'Artist'},
              {'id': 'upcoming', 'title': 'Upcoming', 'artist': 'Artist'},
            ],
            currentIndex: 0,
            positionMs: 10000,
            durationMs: 180000,
            isPlaying: true,
            shuffle: true,
            repeatMode: 'off',
            volume: 0.5,
          ),
          deviceId: 'desktop',
          deviceName: 'Desktop',
          deviceType: 'desktop',
        ),
        sendCommand: (command, [arguments]) =>
            commands.add((command, arguments)));
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });
    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(commands, isEmpty);
    expect(playback.queue.songs.map((s) => s.id), ['current', 'upcoming']);
    await tester.tap(find.text('Play Next'));
    await _pumpFrames(tester);
    expect(commands.single.$1, AriamiConnectCommand.insertQueueTrack);
    expect(commands.single.$2?['index'], 1);
    expect(playback.queue.songs.map((s) => s.id),
        ['current', 'history', 'upcoming']);

    await tester.tap(find.byTooltip('Add to queue'));
    await _pumpFrames(tester);
    expect(commands.length, 2);
    expect(commands.last.$1, AriamiConnectCommand.insertQueueTrack);
    expect(commands.last.$2?['index'], 3);
    expect(playback.queue.songs.map((s) => s.id),
        ['current', 'history', 'upcoming', 'history']);
    expect(playback.currentSong?.id, 'current');
    expect(playback.isPlaying, isTrue);
    expect(playback.isShuffleEnabled, isTrue);

    await tester.tap(find.text('Missing Song'));
    await _pumpFrames(tester);
    expect(find.text('Play Next'), findsNothing);
    expect(commands.length, 2);
    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping available track opens showAriamiSheet with comprehensive actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    expect(find.byType(PopupMenuButton), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    // Header styling: track note icon, title, artist
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.text('History Song'), findsWidgets);
    expect(find.text('Artist'), findsWidgets);

    // Bottom sheet actions
    expect(find.widgetWithText(ListTile, 'Play'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Like song'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Play Next'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Add to Queue'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Add to Playlist'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Show in album'), findsOneWidget);
  });

  testWidgets(
      'tapping track without albumId omits Show in album from bottom sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('no-album-song', 'No Album Song', DateTime.now()),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('No Album Song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Play'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Like song'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Play Next'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Add to Queue'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Add to Playlist'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Show in album'), findsNothing);
  });

  testWidgets(
      'tapping Play in sheet starts playback immediately and closes sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    final commands = <(String, Map<String, dynamic>?)>[];
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: AriamiPlaybackSnapshot(
          queue: [
            {'id': 'current', 'title': 'Current', 'artist': 'Artist'},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 180000,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 0.5,
        ),
        deviceId: 'desktop',
        deviceName: 'Desktop',
        deviceType: 'desktop',
      ),
      sendCommand: (command, [arguments]) =>
          commands.add((command, arguments)),
    );
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Play'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(commands.any((c) => c.$1 == AriamiConnectCommand.playContext), isTrue);

    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping Add to Queue in sheet appends song and shows confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    final commands = <(String, Map<String, dynamic>?)>[];
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: AriamiPlaybackSnapshot(
          queue: [
            {'id': 'current', 'title': 'Current', 'artist': 'Artist'},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 180000,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 0.5,
        ),
        deviceId: 'desktop',
        deviceName: 'Desktop',
        deviceType: 'desktop',
      ),
      sendCommand: (command, [arguments]) =>
          commands.add((command, arguments)),
    );
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Add to Queue'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(commands.length, 1);
    expect(commands.single.$1, AriamiConnectCommand.insertQueueTrack);
    expect(commands.single.$2?['index'], 1);
    expect(find.text('Added to queue'), findsOneWidget);

    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping Play Next in sheet queues song next and shows confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    final commands = <(String, Map<String, dynamic>?)>[];
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: AriamiPlaybackSnapshot(
          queue: [
            {'id': 'first', 'title': 'First', 'artist': 'Artist'},
            {'id': 'second', 'title': 'Second', 'artist': 'Artist'},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 180000,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 0.5,
        ),
        deviceId: 'desktop',
        deviceName: 'Desktop',
        deviceType: 'desktop',
      ),
      sendCommand: (command, [arguments]) =>
          commands.add((command, arguments)),
    );
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Play Next'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(commands.length, 1);
    expect(commands.single.$1, AriamiConnectCommand.insertQueueTrack);
    expect(commands.single.$2?['index'], 1);
    expect(find.text('Playing next'), findsOneWidget);

    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping Like song in sheet toggles favorite status via PlaylistService',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    final playlistService = PlaylistService();
    await playlistService.clearAllPlaylistData();
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    expect(playlistService.isLikedSong('history'), isFalse);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    expect(find.widgetWithText(ListTile, 'Like song'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Like song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(playlistService.isLikedSong('history'), isTrue);

    // Open again to verify it shows Dislike song and toggles back
    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    expect(find.widgetWithText(ListTile, 'Dislike song'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Dislike song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(playlistService.isLikedSong('history'), isFalse);

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping Show in album navigates to AlbumDetailScreen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Show in album'));
    await _pumpFrames(tester);

    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping Add to Playlist in sheet opens playlist picker',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Add to Playlist'));
    await _pumpFrames(tester);

    expect(
      find.descendant(
        of: find.byType(AriamiSheetHeader),
        matching: find.text('Add to Playlist'),
      ),
      findsOneWidget,
    );
    expect(find.text('"History Song" • Artist'), findsOneWidget);

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping unavailable track tile does not open bottom sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('missing-track', 'Missing Track', DateTime.now()),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    expect(find.text('Missing Track'), findsOneWidget);
    await tester.tap(find.text('Missing Track'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Play Next'), findsNothing);

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping trailing quick-add button adds to queue immediately without opening sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    final commands = <(String, Map<String, dynamic>?)>[];
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: AriamiPlaybackSnapshot(
          queue: [
            {'id': 'current', 'title': 'Current', 'artist': 'Artist'},
          ],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 180000,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 0.5,
        ),
        deviceId: 'desktop',
        deviceName: 'Desktop',
        deviceType: 'desktop',
      ),
      sendCommand: (command, [arguments]) =>
          commands.add((command, arguments)),
    );
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    // Quick add button on tile
    await tester.tap(find.byTooltip('Add to queue'));
    await _pumpFrames(tester);

    // Sheet was NOT opened
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Play Next'), findsNothing);

    // Queue action executed and confirmation displayed
    expect(commands.single.$1, AriamiConnectCommand.insertQueueTrack);
    expect(find.text('Added to queue'), findsOneWidget);

    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'stat with empty/whitespace album metadata falls back to library song and enables Show in album',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      SongStats(
        songId: 'history',
        playCount: 1,
        totalTime: const Duration(minutes: 3),
        firstPlayed: DateTime.now(),
        lastPlayed: DateTime.now(),
        songTitle: 'History Song',
        songArtist: 'Artist',
        albumId: '',
        album: '   ',
      ),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    // Verify tile displays resolved album name without broken trailing bullet
    expect(find.text('Artist • History Album'), findsOneWidget);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Show in album'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Show in album'));
    await _pumpFrames(tester);

    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'stat with whitespace-only albumId and no library album omits Show in album',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      SongStats(
        songId: 'no-album-song',
        playCount: 1,
        totalTime: const Duration(minutes: 3),
        firstPlayed: DateTime.now(),
        lastPlayed: DateTime.now(),
        songTitle: 'No Album Song',
        songArtist: 'Artist',
        albumId: '   ',
      ),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('No Album Song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Show in album'), findsNothing);

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'playback error when tapping Play displays error SnackBar gracefully',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('history', 'History Song', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: AriamiPlaybackSnapshot(
          queue: [],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 0,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 1.0,
        ),
        deviceId: 'desktop',
        deviceName: 'Desktop',
        deviceType: 'desktop',
      ),
      sendCommand: (command, [arguments]) {
        if (command == AriamiConnectCommand.playContext) {
          throw Exception('Remote playback failed');
        }
      },
    );
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('History Song'));
    await _pumpFrames(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Play'));
    await _pumpFrames(tester);

    expect(find.text('Could not play “History Song”.'), findsOneWidget);

    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping unavailable track trailing quick-add button does nothing and does not open sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      _play('missing-track', 'Missing Track', DateTime.now()),
    ]);
    final playback = PlaybackManager();
    final commands = <(String, Map<String, dynamic>?)>[];
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: AriamiPlaybackSnapshot(
          queue: [],
          currentIndex: 0,
          positionMs: 0,
          durationMs: 0,
          isPlaying: false,
          shuffle: false,
          repeatMode: 'off',
          volume: 1.0,
        ),
        deviceId: 'desktop',
        deviceName: 'Desktop',
        deviceType: 'desktop',
      ),
      sendCommand: (command, [arguments]) => commands.add((command, arguments)),
    );
    addTearDown(() {
      dismissQueueActionConfirmation();
      playback.setConnectRemoteMirror(null);
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    // Unavailable tile has disabled icon with tooltip 'Unavailable in your library'
    expect(find.byTooltip('Unavailable in your library'), findsOneWidget);
    await tester.tap(find.byTooltip('Unavailable in your library'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(commands, isEmpty);
    expect(find.text('Added to queue'), findsNothing);

    dismissQueueActionConfirmation();
    playback.setConnectRemoteMirror(null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'tapping Show in album for track with missing library album navigates to AlbumDetailScreen with fallback AlbumModel',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StreamingStatsService().setAccountStatsOverlay([
      SongStats(
        songId: 'stale-album-song',
        playCount: 1,
        totalTime: const Duration(minutes: 3),
        firstPlayed: DateTime.now(),
        lastPlayed: DateTime.now(),
        songTitle: 'Stale Album Song',
        songArtist: 'Song Artist',
        albumId: 'deleted-album-id',
        album: 'Deleted Album',
        albumArtist: '   ',
      ),
    ]);
    addTearDown(() {
      dismissQueueActionConfirmation();
      StreamingStatsService().setAccountStatsOverlay(null);
    });

    await tester.pumpWidget(const MaterialApp(home: RecentlyPlayedScreen()));
    await _waitForCatalog(tester);

    await tester.tap(find.text('Stale Album Song'));
    await _pumpFrames(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Show in album'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Show in album'));
    await _pumpFrames(tester);

    expect(find.byType(AlbumDetailScreen), findsOneWidget);
    final albumDetail =
        tester.widget<AlbumDetailScreen>(find.byType(AlbumDetailScreen));
    expect(albumDetail.album.id, 'deleted-album-id');
    expect(albumDetail.album.title, 'Deleted Album');
    // albumArtist with whitespace fell back to song/entry artist
    expect(albumDetail.album.artist, 'Song Artist');

    dismissQueueActionConfirmation();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

