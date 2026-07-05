import 'package:ariami_mobile/services/playback_manager.dart';
import 'package:ariami_mobile/widgets/player/player_output_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  installSqfliteTestMocks();

  testWidgets('shows Ariami Connect before Google Cast', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOutputButton(playbackManager: PlaybackManager()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('player-output-button')));
    await tester.pumpAndSettle();

    final ariamiConnect = find.byKey(
      const ValueKey('ariami-connect-option'),
    );
    final googleCast = find.byKey(const ValueKey('google-cast-option'));

    expect(ariamiConnect, findsOneWidget);
    expect(googleCast, findsOneWidget);
    expect(
      tester.getTopLeft(ariamiConnect).dy,
      lessThan(tester.getTopLeft(googleCast).dy),
    );
    expect(find.byType(Divider), findsOneWidget);
  });
}
