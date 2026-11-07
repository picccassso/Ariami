import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:ariami_mobile/widgets/common/queue_action_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

Song _song(String id) => Song(
      id: id,
      title: id,
      artist: 'Artist',
      duration: const Duration(minutes: 3),
      filePath: '/music/$id.mp3',
      fileSize: 1,
      modifiedTime: DateTime(2026),
    );

/// Pumps a host widget whose button runs [onPressed] with the host context,
/// so tests can drive the same toast helpers the real call sites use.
Future<void> _pumpHost(
  WidgetTester tester,
  void Function(BuildContext context) onPressed,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('trigger'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installSqfliteTestMocks();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await initializeSharedPrefs();
    final manager = PlaybackManager();
    manager.setConnectRemoteMirror(null);
    await manager.stopAndClearQueue();
    // Keep a current song so undoing an addition never hits the
    // "removed the now-playing track" playback path.
    manager.addToQueue(_song('current'));
  });

  testWidgets('add-to-queue toast undo removes the added song',
      (tester) async {
    final manager = PlaybackManager();

    await _pumpHost(tester, (context) {
      final index = manager.addToQueue(_song('undo-me'));
      showQueueAdditionToast(
        context,
        message: 'Added to end of queue',
        firstIndex: index,
      );
    });

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(manager.queue.songs.map((s) => s.id), ['current', 'undo-me']);
    expect(find.text('Added to end of queue'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(manager.queue.songs.map((s) => s.id), ['current']);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('play-next toast undo removes the inserted song',
      (tester) async {
    final manager = PlaybackManager();

    await _pumpHost(tester, (context) {
      final index = manager.playNext(_song('next-up'));
      showQueueAdditionToast(
        context,
        message: 'Playing next',
        firstIndex: index,
      );
    });

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(manager.queue.songs.map((s) => s.id), ['current', 'next-up']);
    expect(find.text('Playing next'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(manager.queue.songs.map((s) => s.id), ['current']);
  });

  testWidgets('batch addition toast undo removes the whole added range',
      (tester) async {
    final manager = PlaybackManager();

    await _pumpHost(tester, (context) {
      final songs = [_song('batch-1'), _song('batch-2'), _song('batch-3')];
      final firstIndex = manager.addAllToQueue(songs);
      showQueueAdditionToast(
        context,
        message: 'Added 3 songs to end of queue',
        firstIndex: firstIndex,
        count: songs.length,
      );
    });

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(
      manager.queue.songs.map((s) => s.id),
      ['current', 'batch-1', 'batch-2', 'batch-3'],
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(manager.queue.songs.map((s) => s.id), ['current']);
  });

  testWidgets('toast can be swiped away without triggering undo',
      (tester) async {
    final manager = PlaybackManager();

    await _pumpHost(tester, (context) {
      final index = manager.addToQueue(_song('swipe-me'));
      showQueueAdditionToast(
        context,
        message: 'Swiped away',
        firstIndex: index,
      );
    });

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Swiped away'), findsOneWidget);
    expect(manager.queue.songs.map((s) => s.id), ['current', 'swipe-me']);

    await tester.drag(find.text('Swiped away'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Swiped away'), findsNothing);
    // Swiping only dismisses the toast; the queued song stays queued.
    expect(manager.queue.songs.map((s) => s.id), ['current', 'swipe-me']);
  });

  testWidgets('toast without a valid index still shows but has no undo',
      (tester) async {
    await _pumpHost(tester, (context) {
      showQueueAdditionToast(
        context,
        message: 'Nothing to add to queue',
        firstIndex: -1,
      );
    });

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to add to queue'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);

    dismissQueueActionConfirmation();
    await tester.pump();
  });
}
