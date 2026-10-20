import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/player/player_output_button.dart';
import 'package:ariami_mobile/widgets/player/player_secondary_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  installSqfliteTestMocks();

  testWidgets('groups song actions in one sheet and keeps the row to four',
      (tester) async {
    final calls = <String>[];
    final playbackManager = PlaybackManager();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerSecondaryControls(
            outputButton: PlayerOutputButton(
              playbackManager: playbackManager,
              showDeviceName: false,
            ),
            outputCaption: PlayerOutputCaption(
              playbackManager: playbackManager,
            ),
            hasLyrics: true,
            onToggleLyrics: () {},
            onOpenQueue: () {},
            onAddToPlaylist: () => calls.add('playlist'),
            onPlayNext: () => calls.add('next'),
            onAddToQueue: () => calls.add('queue'),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.byType(IconButton), findsNWidgets(3));
    expect(find.byKey(const ValueKey('player-output-button')), findsOneWidget);
    // Playing locally: no device caption.
    expect(find.byKey(const ValueKey('player-output-caption')), findsNothing);

    await tester.tap(find.byTooltip('Song options'));
    await tester.pumpAndSettle();
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to end of queue'), findsOneWidget);

    await tester.tap(find.text('Add to playlist'));
    await tester.pumpAndSettle();
    expect(calls, equals(['playlist']));
  });
}
