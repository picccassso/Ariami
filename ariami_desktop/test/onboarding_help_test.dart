import 'package:ariami_desktop/onboarding/onboarding_copy.dart';
import 'package:ariami_desktop/onboarding/setup_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'setup help dialog opens from the header icon and closes via '
      'button, Escape, and barrier tap', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SetupScreenScaffold(
        title: 'Tailscale Setup',
        helpTopic: OnboardingCopy.tailscale,
        body: SizedBox(),
      ),
    ));

    Future<void> open() async {
      await tester.tap(find.byIcon(Icons.info_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text(OnboardingCopy.tailscale.title), findsOneWidget);
      expect(
        find.text(OnboardingCopy.tailscale.sections.first.heading),
        findsOneWidget,
      );
    }

    await open();
    await tester.tap(find.byTooltip('Close help'));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingCopy.tailscale.title), findsNothing);

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(OnboardingCopy.tailscale.title), findsNothing);

    await open();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingCopy.tailscale.title), findsNothing);
  });
}
