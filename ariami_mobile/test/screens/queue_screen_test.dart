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
          onRemove: queue.removeSong,
        ),
      ),
    );

    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsOneWidget);
    expect(find.text('Song c'), findsOneWidget);

    tester
        .widget<Dismissible>(find.byType(Dismissible).at(1))
        .onDismissed
        ?.call(DismissDirection.endToStart);
    await tester.pump();

    expect(queue.songs.map((song) => song.id), ['a', 'c']);
    expect(find.text('Song b'), findsNothing);
    expect(find.text('Song c'), findsOneWidget);

    tester
        .widget<Dismissible>(find.byType(Dismissible).at(1))
        .onDismissed
        ?.call(DismissDirection.endToStart);
    await tester.pump();

    expect(queue.songs.map((song) => song.id), ['a']);
    expect(find.text('Song c'), findsNothing);
  });
}
