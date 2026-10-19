import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/widgets/common/lyrics_badge.dart';

void main() {
  group('LyricsBadge', () {
    testWidgets('renders LYRICS text in pill container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LyricsBadge(),
            ),
          ),
        ),
      );

      expect(find.text('LYRICS'), findsOneWidget);
      expect(find.byType(LyricsBadge), findsOneWidget);
    });
  });
}
