import 'package:ariami_cli/web/widgets/dashboard/owner_access_error_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OwnerAccessErrorPanel invokes sign-in callback', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerAccessErrorPanel(
            message: 'Owner privileges required.',
            onSignInAsOwner: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('SIGN IN AS OWNER'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
