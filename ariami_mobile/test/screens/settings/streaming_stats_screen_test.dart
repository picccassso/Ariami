import 'package:ariami_mobile/screens/settings/streaming_stats_screen.dart';
import 'package:ariami_mobile/services/stats/streaming_stats_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await StreamingStatsService().initialize();
    // The ffi database persists on disk between test files; start clean so
    // the empty states below are deterministic.
    await StreamingStatsService().resetAllStats();
  });

  testWidgets('stats screen loads with the bottom period selector',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamingStatsScreen()));
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
    expect(find.text('All time'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    // No listening yet: the all-time empty state shows.
    expect(find.textContaining('No stats yet'), findsWidgets);
  });

  testWidgets('period views degrade cleanly with no server connection',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamingStatsScreen()));
    await tester.pump();

    await tester.tap(find.text('DAY'));
    await tester.pump();
    await tester.pump();

    // The stepper now shows the picked day.
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
}
