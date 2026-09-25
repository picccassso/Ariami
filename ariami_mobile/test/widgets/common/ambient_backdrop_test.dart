import 'package:ariami_mobile/utils/constants.dart';
import 'package:ariami_mobile/widgets/common/ambient_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget backdrop({required bool moving}) => MaterialApp(
        theme: AppTheme.buildNeutralTheme(brightness: Brightness.dark),
        home: AmbientBackdrop(layoutSeed: 1, moving: moving),
      );

  testWidgets('drifts continuously while moving, then settles to no frames',
      (tester) async {
    await tester.pumpWidget(backdrop(moving: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(backdrop(moving: true));
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(backdrop(moving: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a foreground sits between the glows and the kick flash',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildNeutralTheme(brightness: Brightness.dark),
        home: const AmbientBackdrop(
          moving: true,
          foreground: Text('art'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final stack = tester.widget<Stack>(
      find.ancestor(of: find.text('art'), matching: find.byType(Stack)).first,
    );
    expect(stack.children.map((child) => child.runtimeType), [
      CustomPaint, // glows
      RepaintBoundary, // the foreground
      CustomPaint, // the kick flash, painted over it
    ]);
  });
}
