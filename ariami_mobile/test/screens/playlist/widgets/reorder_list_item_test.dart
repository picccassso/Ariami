import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/playlist/widgets/reorder_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReorderListItem', () {
    testWidgets('should display song title and artist', (tester) async {
      final song = SongModel(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderListItem(
              song: song,
              index: 0,
            ),
          ),
        ),
      );

      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('should display track number', (tester) async {
      final song = SongModel(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderListItem(
              song: song,
              index: 4,
            ),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('should render drag handle', (tester) async {
      final song = SongModel(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderListItem(
              song: song,
              index: 0,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.drag_handle), findsOneWidget);
    });

    testWidgets('should render remove button', (tester) async {
      final song = SongModel(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderListItem(
              song: song,
              index: 0,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });

    testWidgets('should call onRemove when remove button is tapped',
        (tester) async {
      var removeCalled = false;
      final song = SongModel(
        id: '1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderListItem(
              song: song,
              index: 0,
              onRemove: () => removeCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();

      expect(removeCalled, true);
    });
  });
}
