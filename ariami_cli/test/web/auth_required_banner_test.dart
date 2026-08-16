import 'package:ariami_cli/web/widgets/dashboard/auth_required_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AuthRequiredBanner confirms active signed-in session',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AuthRequiredBanner(),
        ),
      ),
    );

    expect(
      find.text(
        'Sign-in is required on this server. '
        'Everyone connecting needs an account.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsNothing);
  });
}
