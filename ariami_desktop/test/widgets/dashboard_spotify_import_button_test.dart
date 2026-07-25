import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_desktop/widgets/dashboard/dashboard_overview_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('overview exposes the Spotify stats import and remove actions',
      (tester) async {
    var imported = false;
    var removed = false;
    await tester.pumpWidget(
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
            onImportSpotifyStats: () => imported = true,
            onRemoveSpotifyStats: () => removed = true,
          ),
        ),
      ),
    );

    final importButton = find.widgetWithText(
      OutlinedButton,
      'Import Spotify listening stats',
    );
    await tester.scrollUntilVisible(importButton, 300);
    expect(importButton, findsOneWidget);
    await tester.tap(importButton);
    expect(imported, isTrue);

    final removeButton = find.widgetWithText(
      OutlinedButton,
      'Remove Spotify listening stats',
    );
    await tester.scrollUntilVisible(removeButton, 300);
    expect(removeButton, findsOneWidget);
    await tester.tap(removeButton);
    expect(removed, isTrue);
  });
}
