import 'package:ariami_mobile/screens/playlist/widgets/playlist_action_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistActionButtons', () {
    Widget buildButtons({
      bool isPlaylistFullyDownloaded = false,
      bool hasSongs = true,
      bool canReorder = true,
      bool isReorderMode = false,
      VoidCallback? onDownloadPlaylist,
      VoidCallback? onPlay,
      VoidCallback? onShuffle,
      VoidCallback? onToggleReorder,
      VoidCallback? onAddSongs,
      VoidCallback? onMoreActions,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: PlaylistActionButtons(
            isPlaylistFullyDownloaded: isPlaylistFullyDownloaded,
            hasSongs: hasSongs,
            canReorder: canReorder,
            isReorderMode: isReorderMode,
            onDownloadPlaylist: onDownloadPlaylist,
            onPlay: onPlay,
            onShuffle: onShuffle,
            onToggleReorder: onToggleReorder,
            onAddSongs: onAddSongs,
            onMoreActions: onMoreActions,
          ),
        ),
      );
    }

    testWidgets('should render all buttons', (tester) async {
      await tester.pumpWidget(buildButtons());

      expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.reorder_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    });

    testWidgets('should call onDownloadPlaylist when Download is tapped',
        (tester) async {
      var downloadCalled = false;

      await tester.pumpWidget(
        buildButtons(onDownloadPlaylist: () => downloadCalled = true),
      );

      await tester.tap(find.byIcon(Icons.download_for_offline_outlined));
      await tester.pump();

      expect(downloadCalled, true);
    });

    testWidgets('should show download_done when fully downloaded',
        (tester) async {
      await tester.pumpWidget(
        buildButtons(isPlaylistFullyDownloaded: true),
      );

      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.download_for_offline_outlined), findsNothing);
    });

    testWidgets('should call onPlay when Play button is tapped',
        (tester) async {
      var playCalled = false;

      await tester.pumpWidget(
        buildButtons(onPlay: () => playCalled = true),
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(playCalled, true);
    });

    testWidgets('should call onShuffle when Shuffle button is tapped',
        (tester) async {
      var shuffleCalled = false;

      await tester.pumpWidget(
        buildButtons(onShuffle: () => shuffleCalled = true),
      );

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump();

      expect(shuffleCalled, true);
    });

    testWidgets('should call onToggleReorder when Reorder button is tapped',
        (tester) async {
      var toggleCalled = false;

      await tester.pumpWidget(
        buildButtons(onToggleReorder: () => toggleCalled = true),
      );

      await tester.tap(find.byIcon(Icons.reorder_rounded));
      await tester.pump();

      expect(toggleCalled, true);
    });

    testWidgets('should show Done when in reorder mode', (tester) async {
      await tester.pumpWidget(buildButtons(isReorderMode: true));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.reorder_rounded), findsNothing);
    });

    testWidgets('should disable Play and Shuffle when no songs',
        (tester) async {
      var playCalled = false;
      var shuffleCalled = false;

      await tester.pumpWidget(
        buildButtons(
          hasSongs: false,
          canReorder: false,
          onPlay: () => playCalled = true,
          onShuffle: () => shuffleCalled = true,
        ),
      );

      final playButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.play_arrow_rounded),
          matching: find.byType(IconButton),
        ),
      );
      final shuffleButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.shuffle_rounded),
          matching: find.byType(IconButton),
        ),
      );

      expect(playButton.onPressed, isNull);
      expect(shuffleButton.onPressed, isNull);

      // Callbacks should not be called since buttons are disabled
      expect(playCalled, false);
      expect(shuffleCalled, false);
    });

    testWidgets('should disable Download when onDownloadPlaylist is null',
        (tester) async {
      await tester.pumpWidget(
        buildButtons(onDownloadPlaylist: null),
      );

      final downloadButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.download_for_offline_outlined),
          matching: find.byType(IconButton),
        ),
      );

      expect(downloadButton.onPressed, isNull);
    });

    testWidgets('should disable Reorder when only one song', (tester) async {
      var reorderCalled = false;

      await tester.pumpWidget(
        buildButtons(
          canReorder: false,
          onToggleReorder: () => reorderCalled = true,
        ),
      );

      final reorderButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.reorder_rounded),
          matching: find.byType(IconButton),
        ),
      );

      expect(reorderButton.onPressed, isNull);

      // Callback should not be called since button is disabled
      expect(reorderCalled, false);
    });

    testWidgets('should call onMoreActions when More Actions button is tapped',
        (tester) async {
      var moreCalled = false;

      await tester.pumpWidget(
        buildButtons(onMoreActions: () => moreCalled = true),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();

      expect(moreCalled, true);
    });
  });
}
