import 'package:ariami_mobile/screens/main/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(installSqfliteTestMocks);

  testWidgets('search scaffold does not resize above the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchScreen(),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
  });

  testWidgets(
    'search navigation focuses, submits, clears, then focuses again',
    (tester) async {
      final reselectionRequests = ValueNotifier<int>(0);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            focusOnOpen: true,
            reselectionRequests: reselectionRequests,
          ),
        ),
      );
      await tester.pump();

      TextField searchField() => tester.widget<TextField>(
            find.byType(TextField),
          );

      expect(searchField().focusNode?.hasFocus, isTrue);

      await tester.enterText(find.byType(TextField), 'Ariami');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(searchField().controller?.text, 'Ariami');
      expect(searchField().focusNode?.hasFocus, isFalse);

      reselectionRequests.value++;
      await tester.pump();

      expect(searchField().controller?.text, isEmpty);
      expect(searchField().focusNode?.hasFocus, isFalse);

      reselectionRequests.value++;
      await tester.pump();

      expect(searchField().focusNode?.hasFocus, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      reselectionRequests.dispose();
    },
  );
}
