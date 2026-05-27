import 'package:ariami_cli/web/utils/web_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('navigateToDashboard', () {
    testWidgets('clears stack so dashboard cannot pop back to setup routes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/welcome': (context) => const Scaffold(
                  body: Center(child: Text('Welcome')),
                ),
            '/dashboard': (context) => Scaffold(
                  appBar: AppBar(
                    automaticallyImplyLeading: false,
                    title: const Text('DASHBOARD'),
                  ),
                  body: const Center(child: Text('Dashboard body')),
                ),
          },
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/welcome');
                      navigateToDashboard(context);
                    },
                    child: const Text('Finish setup'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Finish setup'));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);

      final dashboardContext = tester.element(find.text('Dashboard body'));
      expect(Navigator.of(dashboardContext).canPop(), isFalse);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.automaticallyImplyLeading, isFalse);
    });
  });
}
