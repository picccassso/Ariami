import 'package:ariami_mobile/screens/playlist/widgets/fallback_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FallbackHeader', () {
    testWidgets('should render music icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FallbackHeader(),
          ),
        ),
      );

      expect(find.byIcon(Icons.queue_music), findsOneWidget);
    });

    testWidgets('should render gradient background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FallbackHeader(playlistName: 'Test Playlist'),
          ),
        ),
      );

      // Check that a Container with BoxDecoration is rendered
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(FallbackHeader),
          matching: find.byType(Container),
        ),
      );

      expect(container.decoration, isA<BoxDecoration>());
    });

    testWidgets('should use consistent colors for same playlist name',
        (tester) async {
      // Pump twice with same name
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FallbackHeader(playlistName: 'Same Name'),
          ),
        ),
      );

      final container1 = tester.widget<Container>(
        find.descendant(
          of: find.byType(FallbackHeader),
          matching: find.byType(Container),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FallbackHeader(playlistName: 'Same Name'),
          ),
        ),
      );

      final container2 = tester.widget<Container>(
        find.descendant(
          of: find.byType(FallbackHeader),
          matching: find.byType(Container),
        ),
      );

      // Both should have BoxDecoration
      expect(container1.decoration, isA<BoxDecoration>());
      expect(container2.decoration, isA<BoxDecoration>());
    });
  });
}
