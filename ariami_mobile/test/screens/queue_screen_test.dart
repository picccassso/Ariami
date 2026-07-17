import 'package:ariami_mobile/models/playback_queue.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/screens/queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Song makeSong(String id) => Song(
        id: id,
        title: 'Song $id',
        artist: 'Artist $id',
        duration: const Duration(minutes: 3),
        filePath: id,
        fileSize: 123,
        modifiedTime: DateTime(2026, 1, 1),
      );

  setUpAll(installSqfliteTestMocks);
  tearDownAll(uninstallSqfliteTestMocks);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('removing multiple queue items updates the open queue screen',
      (tester) async {
    final queue = PlaybackQueue(
      songs: [makeSong('a'), makeSong('b'), makeSong('c')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QueueScreen(
          queue: queue,
          onRemove: (index) {
            final removed = queue.songs[index];
            queue.removeSong(index);
            return QueueItemRemoval(
              song: removed,
              index: index,
              wasCurrent: false,
              wasPlaying: false,
              wasOneShot: false,
            );
          },
        ),
      ),
    );

    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsOneWidget);
    expect(find.text('Song c'), findsOneWidget);

    final songCKeyBeforeRemove =
        tester.widget<Dismissible>(find.byType(Dismissible).at(2)).key;

    tester
        .widget<Dismissible>(find.byType(Dismissible).at(1))
        .onDismissed
        ?.call(DismissDirection.endToStart);
    await tester.pump();

    expect(queue.songs.map((song) => song.id), ['a', 'c']);
    expect(find.text('Song b'), findsNothing);
    expect(find.text('Song c'), findsOneWidget);
    expect(
      tester.widget<Dismissible>(find.byType(Dismissible).at(1)).key,
      songCKeyBeforeRemove,
    );

    tester
        .widget<Dismissible>(find.byType(Dismissible).at(1))
        .onDismissed
        ?.call(DismissDirection.endToStart);
    await tester.pump();

    expect(queue.songs.map((song) => song.id), ['a']);
    expect(find.text('Song c'), findsNothing);
  });

  testWidgets('undo toast restores a removed queue item', (tester) async {
    // Phone-width surface: the default 800x600 test view is wide enough to
    // trigger the tablet rail layout, which moves the undo toast. 500 (not a
    // real phone's 390) keeps the summary row from overflowing with the
    // wide test font.
    tester.view.physicalSize = const Size(500, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final queue = PlaybackQueue(
      songs: [makeSong('a'), makeSong('b'), makeSong('c')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QueueScreen(
          queue: queue,
          onRemove: (index) {
            final removed = queue.songs[index];
            queue.removeSong(index);
            return QueueItemRemoval(
              song: removed,
              index: index,
              wasCurrent: false,
              wasPlaying: false,
              wasOneShot: false,
            );
          },
          onUndoRemove: (removal) {
            queue.insertSong(removal.index, removal.song);
          },
        ),
      ),
    );

    tester
        .widget<Dismissible>(find.byType(Dismissible).at(1))
        .onDismissed
        ?.call(DismissDirection.endToStart);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(queue.songs.map((song) => song.id), ['a', 'c']);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pump();

    expect(queue.songs.map((song) => song.id), ['a', 'b', 'c']);
    expect(find.text('Song b'), findsOneWidget);
    expect(find.text('UNDO'), findsNothing);
  });
}
