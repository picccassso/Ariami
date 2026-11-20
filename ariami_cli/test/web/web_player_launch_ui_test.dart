import 'package:ariami_cli/web/widgets/dashboard/dashboard_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardHeader Open Web Player button', () {
    testWidgets('shows and triggers button on desktop and compact widths',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var tapped = false;
      final controller = TabController(
        length: 4,
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: DashboardHeader(
              tabController: controller,
              tabs: const ['Overview', 'Activity', 'Accounts', 'Server'],
              onRefresh: () {},
              onShowQrCode: () {},
              onSignOut: () {},
              onOpenWebPlayer: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Open Web Player'), findsOneWidget);
      await tester.tap(find.text('Open Web Player'));
      expect(tapped, isTrue);

      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: DashboardHeader(
              tabController: controller,
              tabs: const ['Overview', 'Activity', 'Accounts', 'Server'],
              onRefresh: () {},
              onShowQrCode: () {},
              onSignOut: () {},
              onOpenWebPlayer: () {},
            ),
          ),
        ),
      );
      expect(find.byTooltip('Open Web Player'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides button when onOpenWebPlayer is null', (tester) async {
      final controller = TabController(
        length: 4,
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: DashboardHeader(
              tabController: controller,
              tabs: const ['Overview', 'Activity', 'Accounts', 'Server'],
              onRefresh: () {},
              onShowQrCode: () {},
              onSignOut: () {},
            ),
          ),
        ),
      );

      expect(find.text('Open Web Player'), findsNothing);
      expect(find.text('Player'), findsNothing);
    });
  });
}
