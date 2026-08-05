import 'package:ariami_mobile/screens/settings/playback_settings_screen.dart';
import 'package:ariami_mobile/services/audio/gapless_playback_service.dart';
import 'package:ariami_mobile/services/audio/play_buttons_follow_playback_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:ariami_mobile/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installSqfliteTestMocks();

  final gapless = GaplessPlaybackService();
  final playButtons = PlayButtonsFollowPlaybackService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    gapless.resetForTesting();
    playButtons.resetForTesting();
  });

  Finder switchIn(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(SettingsTile),
        ),
        matching: find.byType(Switch),
      );

  testWidgets('gathers the playback controls, quality stays outside',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PlaybackSettingsScreen()),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Gapless Playback',
      'Play Button Follows Playback',
      'Equalizer',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
    expect(find.text('Streaming Quality'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Play Button Follows Playback')).dy,
      lessThan(tester.getTopLeft(find.text('Equalizer')).dy),
    );
  });

  testWidgets('the toggles persist', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PlaybackSettingsScreen()),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchIn('Gapless Playback')).value, isTrue);
    await tester.tap(switchIn('Gapless Playback'));
    await tester.pump();
    expect(tester.widget<Switch>(switchIn('Gapless Playback')).value, isFalse);
    expect(sharedPrefs.getBool(GaplessPlaybackService.preferenceKey), isFalse);

    // Opt-in, so this one starts off.
    final followLabel = 'Play Button Follows Playback';
    expect(tester.widget<Switch>(switchIn(followLabel)).value, isFalse);
    await tester.tap(switchIn(followLabel));
    await tester.pump();
    expect(tester.widget<Switch>(switchIn(followLabel)).value, isTrue);
    expect(
      sharedPrefs.getBool(PlayButtonsFollowPlaybackService.preferenceKey),
      isTrue,
    );
  });
}
