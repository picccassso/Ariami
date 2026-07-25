import 'package:ariami_cli/web/widgets/dashboard/spotify_stats_section.dart';
import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester,
    SpotifyImportStatus? status, {
    VoidCallback? onRemove,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpotifyStatsSection(
              importStatus: status,
              onImportSpotifyStats: () {},
              onRemoveSpotifyStats: onRemove ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  ElevatedButton removeButton(WidgetTester tester) => tester.widget(
        find.widgetWithText(ElevatedButton, 'REMOVE SPOTIFY STATS'),
      );

  testWidgets('describes an existing import and enables removal',
      (tester) async {
    await pumpSection(
      tester,
      SpotifyImportStatus(
        plays: 12431,
        lastImportedAtMs: DateTime(2026, 7, 24, 18, 5).millisecondsSinceEpoch,
        oldestPlayAtMs: DateTime(2019, 1, 3).millisecondsSinceEpoch,
        newestPlayAtMs: DateTime(2026, 3, 14).millisecondsSinceEpoch,
      ),
    );

    expect(
      find.textContaining('12,431 imported plays'),
      findsOneWidget,
      reason: 'six-figure imports need thousands separators',
    );
    expect(find.textContaining('last import 24/7/2026 18:05'), findsOneWidget);
    expect(find.text('Covering 3/1/2019 – 14/3/2026'), findsOneWidget);
    expect(removeButton(tester).onPressed, isNotNull);
  });

  testWidgets('disables removal when nothing is imported', (tester) async {
    await pumpSection(tester, SpotifyImportStatus.none);

    expect(find.text('No Spotify plays imported.'), findsOneWidget);
    expect(find.textContaining('Covering'), findsNothing);
    expect(removeButton(tester).onPressed, isNull);
  });

  testWidgets('keeps removal reachable while the status is unknown',
      (tester) async {
    await pumpSection(tester, null);

    expect(
      find.text('Checking for an imported Spotify history…'),
      findsOneWidget,
    );
    expect(removeButton(tester).onPressed, isNotNull);
  });
}
