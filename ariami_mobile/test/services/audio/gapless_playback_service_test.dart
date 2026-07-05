import 'package:ariami_mobile/services/audio/gapless_playback_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = GaplessPlaybackService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    service.resetForTesting();
  });

  test('defaults gapless playback to enabled', () {
    service.initialize();

    expect(service.isEnabled, isTrue);
  });

  test('persists and reloads the selected value', () async {
    service.initialize();
    await service.setEnabled(false);

    expect(service.isEnabled, isFalse);
    expect(
      sharedPrefs.getBool(GaplessPlaybackService.preferenceKey),
      isFalse,
    );

    service.resetForTesting();
    service.initialize();
    expect(service.isEnabled, isFalse);
  });

  test('notifies listeners only when the value changes', () async {
    service.initialize();
    var notificationCount = 0;
    void listener() => notificationCount++;
    service.addListener(listener);

    await service.setEnabled(true);
    await service.setEnabled(false);
    await service.setEnabled(false);

    service.removeListener(listener);
    expect(notificationCount, 1);
  });
}
