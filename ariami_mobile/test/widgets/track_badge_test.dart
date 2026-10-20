import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/widgets/common/track_badge.dart';

void main() {
  group('TrackBadge', () {
    Future<void> pump(WidgetTester tester, TrackBadge badge) => tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: badge))));

    testWidgets('shows LYRICS when the track has lyrics', (tester) async {
      await pump(
          tester, const TrackBadge(hasLyrics: true, isInstrumental: true));
      expect(find.text('LYRICS'), findsOneWidget);
      expect(find.text('INST'), findsNothing);
    });

    testWidgets('shows INST for instrumental tracks', (tester) async {
      await pump(
          tester, const TrackBadge(hasLyrics: false, isInstrumental: true));
      expect(find.text('INST'), findsOneWidget);
    });

    testWidgets('shows nothing without either flag', (tester) async {
      await pump(
          tester, const TrackBadge(hasLyrics: false, isInstrumental: false));
      expect(find.byType(Text), findsNothing);
    });
  });
}
