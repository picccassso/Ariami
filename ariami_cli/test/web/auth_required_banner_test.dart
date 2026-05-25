import 'package:ariami_cli/web/screens/login_screen.dart';
import 'package:ariami_cli/web/widgets/dashboard/auth_required_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AuthRequiredBanner sign-in navigates to /login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => const Scaffold(
                body: AuthRequiredBanner(),
              ),
          '/login': (context) => const LoginScreen(),
        },
      ),
    );

    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
