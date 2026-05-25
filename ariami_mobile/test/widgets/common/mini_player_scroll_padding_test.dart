import 'package:ariami_mobile/widgets/common/bottom_chrome_metrics.dart';
import 'package:ariami_mobile/widgets/common/mini_player_aware_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  setUpAll(installSqfliteTestMocks);

  setUp(() {
    while (MiniPlayerVisibility.instance.isFullPlayerOnTop) {
      MiniPlayerVisibility.popFullPlayer();
    }
  });

  testWidgets('scroll padding stays stable while full player is open', (
    tester,
  ) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final scrollPaddingBefore =
        getMiniPlayerScrollBottomPadding(capturedContext);
    expect(scrollPaddingBefore, greaterThan(0));

    MiniPlayerVisibility.pushFullPlayer();

    expect(
      getMiniPlayerScrollBottomPadding(capturedContext),
      scrollPaddingBefore,
    );
    expect(getMiniPlayerAwareBottomPadding(capturedContext), 0);

    MiniPlayerVisibility.popFullPlayer();

    expect(
      getMiniPlayerScrollBottomPadding(capturedContext),
      scrollPaddingBefore,
    );
    expect(
      getMiniPlayerAwareBottomPadding(capturedContext),
      scrollPaddingBefore,
    );
  });

  testWidgets('MiniPlayerScrollPaddingBuilder uses stable scroll padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MiniPlayerScrollPaddingBuilder(
          builder: (context, bottomPadding) {
            return Text('padding:$bottomPadding');
          },
        ),
      ),
    );

    final textBefore = tester.widget<Text>(find.byType(Text)).data!;
    final paddingBefore =
        double.parse(textBefore.replaceFirst('padding:', ''));

    MiniPlayerVisibility.pushFullPlayer();
    await tester.pump();

    final textDuring = tester.widget<Text>(find.byType(Text)).data!;
    final paddingDuring =
        double.parse(textDuring.replaceFirst('padding:', ''));

    expect(paddingDuring, paddingBefore);
    expect(paddingBefore, greaterThanOrEqualTo(kBottomNavigationBarHeight));
  });
}
