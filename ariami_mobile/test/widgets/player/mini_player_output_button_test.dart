import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/player/mini_player.dart';
import 'package:ariami_mobile/widgets/player/player_output_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  installSqfliteTestMocks();

  testWidgets('mini player uses the icon-only output chooser', (tester) async {
    var fullPlayerOpened = false;
    final song = Song(
      id: 'song-1',
      title: 'Troublemaker',
      artist: 'Olly Murs',
      duration: const Duration(minutes: 3),
      filePath: '/music/troublemaker.mp3',
      fileSize: 1,
      modifiedTime: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(
              currentSong: song,
              isPlaying: true,
              isVisible: true,
              onTap: () => fullPlayerOpened = true,
              onPlayPause: () {},
              onSkipNext: () {},
              onSkipPrevious: () {},
              hasNext: false,
              hasPrevious: false,
              position: const Duration(seconds: 10),
              duration: song.duration,
              playbackManager: PlaybackManager(),
            ),
          ),
        ),
      ),
    );

    final outputButton = tester.widget<PlayerOutputButton>(
      find.byType(PlayerOutputButton),
    );
    expect(outputButton.showDeviceName, isFalse);

    await tester.tap(find.byKey(const ValueKey('player-output-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(fullPlayerOpened, isFalse);
    expect(find.byKey(const ValueKey('ariami-connect-option')), findsOneWidget);
    expect(find.byKey(const ValueKey('google-cast-option')), findsOneWidget);
  });
}
