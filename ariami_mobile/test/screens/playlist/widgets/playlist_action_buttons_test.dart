import 'package:ariami_mobile/screens/playlist/widgets/playlist_action_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistActionButtons', () {
    testWidgets('should render all buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: true,
              canReorder: true,
              isReorderMode: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.reorder_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('should call onPlay when Play button is tapped',
        (tester) async {
      var playCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: true,
              canReorder: true,
              isReorderMode: false,
              onPlay: () => playCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(playCalled, true);
    });

    testWidgets('should call onShuffle when Shuffle button is tapped',
        (tester) async {
      var shuffleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: true,
              canReorder: true,
              isReorderMode: false,
              onShuffle: () => shuffleCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump();

      expect(shuffleCalled, true);
    });

    testWidgets('should call onToggleReorder when Reorder button is tapped',
        (tester) async {
      var toggleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: true,
              canReorder: true,
              isReorderMode: false,
              onToggleReorder: () => toggleCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.reorder_rounded));
      await tester.pump();

      expect(toggleCalled, true);
    });

    testWidgets('should show Done when in reorder mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: true,
              canReorder: true,
              isReorderMode: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.reorder_rounded), findsNothing);
    });

    testWidgets('should disable Play and Shuffle when no songs',
        (tester) async {
      var playCalled = false;
      var shuffleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: false,
              canReorder: false,
              isReorderMode: false,
              onPlay: () => playCalled = true,
              onShuffle: () => shuffleCalled = true,
            ),
          ),
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

    testWidgets('should disable Reorder when only one song', (tester) async {
      var reorderCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistActionButtons(
              hasSongs: true,
              canReorder: false,
              isReorderMode: false,
              onToggleReorder: () => reorderCalled = true,
            ),
          ),
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
  });
}
