import 'package:ariami_mobile/screens/settings/stats/streaming_stats_screen.dart';
import 'package:ariami_mobile/models/song_stats.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initializeSharedPrefs();
    await StreamingStatsService().initialize();
    // The ffi database persists on disk between test files; start clean so
    // the empty states below are deterministic.
    await StreamingStatsService().resetAllStats();
  });

  testWidgets('stats screen loads with the bottom period selector',
      (tester) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
    );
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: const StreamingStatsScreen()),
    );
    await tester.pump();

    // Existing structure still loads: tabs plus the bottom selector bar.
    expect(find.text('TRACKS'), findsOneWidget);
    expect(find.text('ARTISTS'), findsOneWidget);
    expect(find.text('ALBUMS'), findsOneWidget);
    expect(find.text('DAY'), findsOneWidget);
    expect(find.text('WEEK'), findsOneWidget);
    expect(find.text('MONTH'), findsOneWidget);
    expect(find.text('YEAR'), findsOneWidget);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    final selectedChip = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('DAY'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(
      (selectedChip.decoration as BoxDecoration).color,
      theme.colorScheme.secondary,
    );
    expect(
      tester.widget<Text>(find.text('DAY')).style?.color,
      theme.colorScheme.onSecondary,
    );
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byTooltip('Reset statistics'), findsNothing);

    // With no server connection, the default day view explains why period
    // stats are unavailable.
    expect(
      find.textContaining('need a connection to your server'),
      findsOneWidget,
    );
  });

  testWidgets('period views degrade cleanly with no server connection',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamingStatsScreen()));
    await tester.pump();

    // Day is selected by default whenever the screen opens.
    expect(find.text('Today'), findsOneWidget);

    // Offline (no api client): a clear message rather than a crash/spinner.
    expect(
      find.textContaining('need a connection to your server'),
      findsOneWidget,
    );

    // Back to all-time restores the local view. (Two pumps: the stream
    // emission on re-subscribe is deferred a microtask.)
    await tester.tap(find.text('ALL'));
    await tester.pump();
    await tester.pump();
    expect(find.text('All time'), findsOneWidget);
    expect(find.textContaining('No stats yet'), findsWidgets);
  });

  testWidgets('year uses all-time totals when all history is in that year',
      (tester) async {
    final service = StreamingStatsService();
    final now = DateTime.now();
    addTearDown(() => service.setAccountStatsOverlay(null));

    await tester.pumpWidget(const MaterialApp(home: StreamingStatsScreen()));
    await tester.pump();
    service.setAccountStatsOverlay([
      SongStats(
        songId: 'current-year-song',
        playCount: 4,
        totalTime: const Duration(hours: 2),
        firstPlayed: DateTime(now.year, 1, 1),
        lastPlayed: now,
        songTitle: 'Current Year Song',
        songArtist: 'Current Year Artist',
      ),
    ]);
    await tester.pump();

    await tester.tap(find.text('YEAR'));
    await tester.pump();

    expect(find.text('${now.year}'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(
      find.textContaining('need a connection to your server'),
      findsNothing,
    );
  });
}
