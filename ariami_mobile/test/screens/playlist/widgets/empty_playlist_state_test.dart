import 'package:ariami_mobile/screens/playlist/widgets/empty_playlist_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmptyPlaylistState', () {
    testWidgets('should render empty state message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyPlaylistState(),
          ),
        ),
      );

      expect(find.text('No songs in this playlist'), findsOneWidget);
      expect(find.text('Tap + to add songs'), findsOneWidget);
    });

    testWidgets('should render music icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyPlaylistState(),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });
}
