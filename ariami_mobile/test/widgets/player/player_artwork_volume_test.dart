import 'package:ariami_mobile/models/playback_queue.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/widgets/player/player_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(installSqfliteTestMocks);
  late PlaybackQueue queue;
  late String? outputId;
  late double volume;
  late String label;
  late List<double> changes;
  late int finishes;
  late List<int> pages;
  late StateSetter rebuild;

  setUp(() {
    queue = PlaybackQueue(songs: [
      for (var i = 0; i < 3; i++)
        Song(
          id: 'volume-artwork-$i',
          title: 'Song $i',
          artist: 'Artist',
          duration: const Duration(minutes: 3),
          filePath: '/song-$i.mp3',
          fileSize: 1,
          modifiedTime: DateTime(2026),
        ),
    ]);
    outputId = 'desktop-a';
    volume = 0.4;
    label = 'Desktop volume';
    changes = [];
    finishes = 0;
    pages = [];
  });

  Future<void> pumpArtwork(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 350,
            height: 350,
            child: StatefulBuilder(builder: (context, setState) {
              rebuild = setState;
              return PlayerArtwork(
                queue: queue,
                currentIndex: 0,
                onPageChanged: pages.add,
                volumeOutputId: outputId,
                volume: volume,
                volumeLabel: label,
                onVolumeChanged: (value) {
                  changes.add(value);
                  rebuild(() => volume = value);
                },
                onVolumeChangeEnd: () => finishes++,
              );
            }),
          ),
        ),
      ),
    ));
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  Future<TestGesture> startSwipe(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PlayerArtwork)),
    );
    // Cross the gesture threshold separately from the measured volume drag.
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    return gesture;
  }

  testWidgets('shows the existing hint for three seconds', (tester) async {
    await pumpArtwork(tester);
    expect(find.text('Slide up and down the cover art to control volume'),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byKey(const ValueKey('cast-volume-hint')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const ValueKey('cast-volume-hint')), findsNothing);
  });

  testWidgets('vertical drag uses existing sensitivity, label, and dismissal',
      (tester) async {
    await pumpArtwork(tester);
    final gesture = await startSwipe(tester);
    await gesture.moveBy(const Offset(0, -56));
    await tester.pump();
    expect(volume, closeTo(0.6, 0.001));
    expect(find.text('Desktop volume 60%'), findsOneWidget);
    await gesture.moveBy(const Offset(0, 28));
    await tester.pump();
    expect(volume, closeTo(0.5, 0.001));
    expect(find.text('Desktop volume 50%'), findsOneWidget);
    await gesture.up();
    expect(finishes, 1);
    expect(pages, isEmpty);
    await tester.pump(const Duration(milliseconds: 899));
    expect(find.byKey(const ValueKey('cast-volume-hud')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const ValueKey('cast-volume-hud')), findsNothing);
  });

  testWidgets('idle receiver updates and the next gesture use current volume',
      (tester) async {
    label = 'Cast volume';
    await pumpArtwork(tester);
    var gesture = await startSwipe(tester);
    await gesture.moveBy(const Offset(0, -28));
    await gesture.up();
    await tester.pump();
    expect(find.text('Cast volume 50%'), findsOneWidget);
    rebuild(() => volume = 0.2);
    await tester.pump();
    expect(find.text('Cast volume 20%'), findsOneWidget);
    gesture = await startSwipe(tester);
    await gesture.moveBy(const Offset(0, -28));
    await tester.pump();
    expect(volume, closeTo(0.3, 0.001));
    await gesture.up();
  });

  testWidgets(
      'changing output ends the old gesture without touching the new one',
      (tester) async {
    await pumpArtwork(tester);
    final gesture = await startSwipe(tester);
    await gesture.moveBy(const Offset(0, -28));
    await tester.pump();
    final count = changes.length;
    rebuild(() {
      outputId = 'desktop-b';
      volume = 0.2;
    });
    await tester.pump();
    await gesture.moveBy(const Offset(0, -28));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(changes.length, count);
    expect(finishes, 0);
    expect(volume, 0.2);
    expect(find.byKey(const ValueKey('cast-volume-hud')), findsNothing);
    expect(find.byKey(const ValueKey('cast-volume-hint')), findsOneWidget);
  });

  testWidgets('unavailable outputs have no vertical volume controls',
      (tester) async {
    outputId = null;
    await pumpArtwork(tester);
    await tester.drag(find.byType(PlayerArtwork), const Offset(0, -100));
    await tester.pump();
    expect(changes, isEmpty);
    expect(finishes, 0);
    expect(find.byKey(const ValueKey('cast-volume-hud')), findsNothing);
    expect(find.byKey(const ValueKey('cast-volume-hint')), findsNothing);
  });

  testWidgets('horizontal track swiping remains independent of volume',
      (tester) async {
    await pumpArtwork(tester);
    await tester.drag(find.byType(PlayerArtwork), const Offset(-250, 0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(pages, contains(1));
    expect(changes, isEmpty);
    expect(finishes, 0);
  });
}
