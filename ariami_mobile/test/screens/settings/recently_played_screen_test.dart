import 'dart:io';

import 'package:ariami_mobile/models/song_stats.dart';
import 'package:ariami_mobile/screens/settings/recently_played_screen.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/private_sqflite_ffi.dart';

SongStats _play(String id, String title, DateTime at) => SongStats(
      songId: id,
      playCount: 1,
      totalTime: const Duration(minutes: 3),
      firstPlayed: at,
      lastPlayed: at,
      songTitle: title,
      songArtist: 'Artist',
    );

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    // Private database and storage: `flutter test` runs files concurrently
    // and the shared FFI directory is not safe to reset from here.
    tempDir = await initPrivateSqfliteFfi('ariami_recently_played_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
    await StreamingStatsService().initialize();
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  testWidgets('the last week opens, older days wait and carry a past year',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    // The account overlay is the display source; no server is needed for it.
    StreamingStatsService().setAccountStatsOverlay([
      _play('song-today', 'Today Song', today),
      _play(
          'song-recent',
          'Recent Song',
          today.subtract(
            const Duration(days: 3),
          )),
      _play(
          'song-month',
          'Last Month Song',
          today.subtract(
            const Duration(days: 25),
          )),
      _play('song-old', 'Old Song', DateTime(2019, 7, 20, 12)),
    ]);
    addTearDown(() => StreamingStatsService().setAccountStatsOverlay(null));

    await tester.pumpWidget(
      const MaterialApp(home: RecentlyPlayedScreen()),
    );
    // Artwork placeholders spin forever offline, so settle by hand.
    await _pumpFrames(tester);

    // Within the last week: open on arrival.
    expect(find.text('Today Song'), findsOneWidget);
    expect(find.text('Recent Song'), findsOneWidget);
    // Older: the day is listed, its tracks are not built until asked for.
    expect(find.text('Last Month Song'), findsNothing);
    expect(find.text('Old Song'), findsNothing);

    // Past years are spelled out; the current year never is.
    expect(find.textContaining(', 2019'), findsOneWidget);
    expect(find.textContaining(', ${now.year}'), findsNothing);

    await tester.tap(find.textContaining(', 2019'));
    await _pumpFrames(tester);

    expect(find.text('Old Song'), findsOneWidget);
    // Opening one old day leaves the others alone.
    expect(find.text('Last Month Song'), findsNothing);
  });
}
