import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_mobile/screens/full_player_screen.dart';
import 'package:ariami_mobile/screens/main/artist_page_opener.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/common/queue_action_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/sqflite_mock.dart';

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AriamiRemotePlayback _remote({
  required String artist,
  required String title,
}) {
  return AriamiRemotePlayback(
    snapshot: AriamiPlaybackSnapshot(
      queue: [
        {'id': 's1', 'title': title, 'artist': artist},
      ],
      currentIndex: 0,
      positionMs: 0,
      durationMs: 180000,
      isPlaying: false,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
      sourceId: 'test',
    ),
    deviceId: 'desktop',
    deviceName: 'Ariami Desktop',
    deviceType: 'desktop',
  );
}

void main() {
  setUpAll(installSqfliteTestMocks);

  tearDown(() {
    dismissQueueActionConfirmation();
    PlaybackManager().setConnectRemoteMirror(null);
  });

  testWidgets('tapping multi-artist in full player opens picker and navigates on selection',
      (tester) async {
    String? openedArtist;
    void onOpenArtist(String name) => openedArtist = name;
    ArtistPageOpener().register(onOpenArtist);
    addTearDown(() => ArtistPageOpener().unregister(onOpenArtist));

    PlaybackManager().setConnectRemoteMirror(
      _remote(artist: 'Costi, Alina', title: 'Necazuri si suparari'),
      sendCommand: (_, [__]) {},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullPlayerScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);

    // Tap on the artist marquee in the full player
    final artistFinder = find.byKey(const ValueKey('artist-s1-Costi, Alina'));
    expect(artistFinder, findsOneWidget);
    await tester.tap(artistFinder, warnIfMissed: false);
    await _pumpFrames(tester);

    // Verify sheet appears with "Artists" header and both options
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Necazuri si suparari'), findsWidgets);
    expect(find.text('Costi'), findsOneWidget);
    expect(find.text('Alina'), findsOneWidget);
    expect(openedArtist, isNull);

    // Tap "Alina"
    await tester.tap(find.text('Alina'));
    await _pumpFrames(tester);

    expect(openedArtist, 'Alina');
    expect(find.text('Artists'), findsNothing);
  });

  testWidgets('tapping single artist in full player navigates immediately without sheet',
      (tester) async {
    String? openedArtist;
    void onOpenArtist(String name) => openedArtist = name;
    ArtistPageOpener().register(onOpenArtist);
    addTearDown(() => ArtistPageOpener().unregister(onOpenArtist));

    PlaybackManager().setConnectRemoteMirror(
      _remote(artist: 'Daft Punk', title: 'One More Time'),
      sendCommand: (_, [__]) {},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullPlayerScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);

    final artistFinder = find.byKey(const ValueKey('artist-s1-Daft Punk'));
    expect(artistFinder, findsOneWidget);
    await tester.tap(artistFinder, warnIfMissed: false);
    await _pumpFrames(tester);

    expect(find.text('Artists'), findsNothing);
    expect(openedArtist, 'Daft Punk');
  });
}
