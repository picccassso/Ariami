import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_desktop/widgets/dashboard/dashboard_overview_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOverview(
    WidgetTester tester, {
    required SpotifyImportStatus? status,
    VoidCallback? onImport,
    VoidCallback? onRemove,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardOverviewTab(
            httpServer: AriamiHttpServer(),
            connectedClients: 0,
            hasOwnerAccount: true,
            availableUpdate: null,
            onToggleServer: () {},
            onOpenOwnerSetup: () {},
            onOpenReleasePage: () {},
            onImportSpotifyStats: onImport ?? () {},
            onRemoveSpotifyStats: onRemove ?? () {},
            spotifyImportStatus: status,
          ),
        ),
      ),
    );
  }

  Finder importButton() => find.widgetWithText(
        OutlinedButton,
        'Import Spotify listening stats',
      );

  Finder removeButton() => find.widgetWithText(
        OutlinedButton,
        'Remove Spotify listening stats',
      );

  testWidgets('exposes the Spotify import and remove actions', (tester) async {
    var imported = false;
    var removed = false;
    await pumpOverview(
      tester,
      status: SpotifyImportStatus(
        plays: 12431,
        lastImportedAtMs: DateTime(2026, 7, 24, 18, 5).millisecondsSinceEpoch,
        oldestPlayAtMs: DateTime(2019, 1, 3).millisecondsSinceEpoch,
        newestPlayAtMs: DateTime(2026, 3, 14).millisecondsSinceEpoch,
      ),
      onImport: () => imported = true,
      onRemove: () => removed = true,
    );

    await tester.scrollUntilVisible(importButton(), 300);
    await tester.tap(importButton());
    expect(imported, isTrue);

    await tester.scrollUntilVisible(removeButton(), 300);
    await tester.tap(removeButton());
    expect(removed, isTrue);
  });

  testWidgets('describes an existing import', (tester) async {
    await pumpOverview(
      tester,
      status: SpotifyImportStatus(
        plays: 12431,
        lastImportedAtMs: DateTime(2026, 7, 24, 18, 5).millisecondsSinceEpoch,
        oldestPlayAtMs: DateTime(2019, 1, 3).millisecondsSinceEpoch,
        newestPlayAtMs: DateTime(2026, 3, 14).millisecondsSinceEpoch,
      ),
    );

    await tester.scrollUntilVisible(removeButton(), 300);
    expect(
      find.textContaining('12,431 imported plays'),
      findsOneWidget,
      reason: 'six-figure imports need thousands separators',
    );
    expect(find.text('Covering 3/1/2019 – 14/3/2026'), findsOneWidget);
  });

  testWidgets('disables removal when nothing is imported', (tester) async {
    await pumpOverview(tester, status: SpotifyImportStatus.none);

    await tester.scrollUntilVisible(removeButton(), 300);
    expect(find.text('No Spotify plays imported.'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(removeButton()).onPressed,
      isNull,
    );
  });

  testWidgets('keeps removal reachable while the status is unknown',
      (tester) async {
    await pumpOverview(tester, status: null);

    await tester.scrollUntilVisible(removeButton(), 300);
    expect(
      find.text('Checking for an imported Spotify history…'),
      findsOneWidget,
    );
    expect(
      tester.widget<OutlinedButton>(removeButton()).onPressed,
      isNotNull,
    );
  });
}
