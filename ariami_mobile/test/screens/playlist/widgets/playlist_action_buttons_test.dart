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

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Reorder'), findsOneWidget);
      expect(find.text('Add Songs'), findsOneWidget);
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

      await tester.tap(find.text('Play'));
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

      await tester.tap(find.text('Shuffle'));
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

      await tester.tap(find.text('Reorder'));
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

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Reorder'), findsNothing);
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

      // Try tapping Play and Shuffle - should not trigger callbacks
      await tester.tap(find.text('Play'));
      await tester.tap(find.text('Shuffle'));
      await tester.pump();

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

      // Try tapping Reorder - should not trigger callback
      await tester.tap(find.text('Reorder'));
      await tester.pump();

      // Callback should not be called since button is disabled
      expect(reorderCalled, false);
    });
  });
}
