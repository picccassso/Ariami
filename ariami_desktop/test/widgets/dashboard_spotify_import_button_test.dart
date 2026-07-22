import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_desktop/widgets/dashboard/dashboard_overview_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('overview exposes the Spotify stats import action',
      (tester) async {
    var tapped = false;
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
            onImportSpotifyStats: () => tapped = true,
          ),
        ),
      ),
    );

    final button = find.widgetWithText(
      OutlinedButton,
      'Import Spotify listening stats',
    );
    await tester.scrollUntilVisible(button, 300);
    expect(button, findsOneWidget);
    await tester.tap(button);
    expect(tapped, isTrue);
  });
}
