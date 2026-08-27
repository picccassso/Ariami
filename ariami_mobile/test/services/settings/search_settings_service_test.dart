import 'package:ariami_mobile/services/settings/search_settings_service.dart';
import 'package:ariami_mobile/utils/shared_preferences_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = SearchSettingsService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeSharedPrefs();
    service.resetForTesting();
  });

  test('defaults SearchMode to spotify (isSpotifyMode = true)', () {
    service.initialize();

    expect(service.mode, SearchMode.spotify);
    expect(service.isSpotifyMode, isTrue);
    expect(SearchSettingsService.preferenceKey, 'search_mode');
  });

  test('loads existing standard mode value from SharedPreferences on initialize', () async {
    SharedPreferences.setMockInitialValues({
      SearchSettingsService.preferenceKey: 'standard',
    });
    await initializeSharedPrefs();
    service.resetForTesting();

    service.initialize();
    expect(service.mode, SearchMode.standard);
    expect(service.isSpotifyMode, isFalse);
  });

  test('loads existing spotify mode value from SharedPreferences on initialize', () async {
    SharedPreferences.setMockInitialValues({
      SearchSettingsService.preferenceKey: 'spotify',
    });
    await initializeSharedPrefs();
    service.resetForTesting();

    service.initialize();
    expect(service.mode, SearchMode.spotify);
    expect(service.isSpotifyMode, isTrue);
  });

  test('persists and reloads the selected search mode', () async {
    service.initialize();
    await service.setMode(SearchMode.standard);

    expect(service.mode, SearchMode.standard);
    expect(service.isSpotifyMode, isFalse);
    expect(
      sharedPrefs.getString(SearchSettingsService.preferenceKey),
      'standard',
    );

    // Simulate app restart / reset
    service.resetForTesting();
    service.initialize();
    expect(service.mode, SearchMode.standard);
    expect(service.isSpotifyMode, isFalse);

    // Switch back to spotify
    await service.setMode(SearchMode.spotify);
    expect(service.mode, SearchMode.spotify);
    expect(service.isSpotifyMode, isTrue);
    expect(
      sharedPrefs.getString(SearchSettingsService.preferenceKey),
      'spotify',
    );
  });

  test('notifies listeners only when the value actually changes', () async {
    service.initialize();
    var notificationCount = 0;
    void listener() => notificationCount++;
    service.addListener(listener);

    await service.setMode(SearchMode.spotify); // No change from initial spotify
    expect(notificationCount, 0);

    await service.setMode(SearchMode.standard); // spotify -> standard: 1 notification
    expect(notificationCount, 1);

    await service.setMode(SearchMode.standard); // Idempotent: 1 notification
    expect(notificationCount, 1);

    await service.setMode(SearchMode.spotify); // standard -> spotify: 2 notifications
    expect(notificationCount, 2);

    service.removeListener(listener);
    await service.setMode(SearchMode.standard); // Removed listener: count stays 2
    expect(notificationCount, 2);
  });

  test('initialize is idempotent and safe to call multiple times', () {
    service.initialize();
    service.initialize();
    expect(service.mode, SearchMode.spotify);
  });

  test('factory constructor returns the singleton instance', () {
    final instance1 = SearchSettingsService();
    final instance2 = SearchSettingsService();
    expect(identical(instance1, instance2), isTrue);
  });

  test('SearchMode extension labels and descriptions', () {
    expect(SearchMode.standard.label, 'Standard');
    expect(SearchMode.spotify.label, 'Spotify Mode');
    expect(SearchMode.standard.description.isNotEmpty, isTrue);
    expect(SearchMode.spotify.description.isNotEmpty, isTrue);
  });
}
