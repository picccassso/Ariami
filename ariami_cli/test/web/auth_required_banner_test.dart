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
          'You are signed in. Authentication is enabled for this server.'),
      findsOneWidget,
    );
    expect(find.text('SIGN IN'), findsNothing);
  });
}
