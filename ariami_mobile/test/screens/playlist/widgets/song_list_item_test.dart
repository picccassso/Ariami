import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/playlist/widgets/song_list_item.dart';
import 'package:ariami_mobile/services/api/connection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  SongModel buildSong() {
    return SongModel(
      id: 'song-1',
      title: 'Track One',
      artist: 'Artist One',
      duration: 240,
    );
  }

  Widget buildSubject({required VoidCallback onRemove}) {
    return MaterialApp(
      home: Scaffold(
        body: SongListItem(
          song: buildSong(),
          index: 0,
          isAvailable: true,
          isDownloaded: false,
          connectionService: ConnectionService(),
          onRemove: onRemove,
        ),
      ),
    );
  }

  Future<void> pumpSwipeFrame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('SongListItem swipe-to-delete', () {
    testWidgets('removes song on intentional center-origin swipe',
        (tester) async {
      var removeCallCount = 0;

      await tester.pumpWidget(
        buildSubject(onRemove: () => removeCallCount++),
      );

      final dismissible = find.byType(Dismissible);
      await tester.fling(dismissible, const Offset(-1000, 0), 2200);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      expect(removeCallCount, 1);
    });

    testWidgets('does not remove song when swipe starts near screen edge',
        (tester) async {
      var removeCallCount = 0;

      await tester.pumpWidget(
        buildSubject(onRemove: () => removeCallCount++),
      );

      final dismissible = find.byType(Dismissible);
      final rect = tester.getRect(dismissible);
      final start = Offset(rect.right - 2, rect.center.dy);

      await tester.dragFrom(start, Offset(-rect.width * 0.85, 0));
      await pumpSwipeFrame(tester);

      expect(removeCallCount, 0);
      expect(find.byType(SongListItem), findsOneWidget);
    });

    testWidgets('does not remove song on short swipe', (tester) async {
      var removeCallCount = 0;

      await tester.pumpWidget(
        buildSubject(onRemove: () => removeCallCount++),
      );

      final dismissible = find.byType(Dismissible);
      final rect = tester.getRect(dismissible);
      final start = rect.center;

      await tester.dragFrom(start, Offset(-rect.width * 0.3, 0));
      await pumpSwipeFrame(tester);

      expect(removeCallCount, 0);
      expect(find.byType(SongListItem), findsOneWidget);
    });
  });
}
