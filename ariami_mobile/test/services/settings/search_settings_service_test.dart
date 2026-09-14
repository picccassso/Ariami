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

  group('Recent searches limit settings', () {
    test('defaults to Standard (30)', () {
      service.initialize();

      expect(service.isCustomRecentLimit, isFalse);
      expect(service.customRecentLimit, 30);
      expect(service.recentSearchesLimit, 30);
      expect(service.recentSearchesLimitLabel, 'Standard (30)');
    });

    test('loads custom limit from SharedPreferences on initialize', () async {
      SharedPreferences.setMockInitialValues({
        SearchSettingsService.recentSearchesIsCustomKey: true,
        SearchSettingsService.recentSearchesLimitKey: 75,
      });
      await initializeSharedPrefs();
      service.resetForTesting();

      service.initialize();
      expect(service.isCustomRecentLimit, isTrue);
      expect(service.customRecentLimit, 75);
      expect(service.recentSearchesLimit, 75);
      expect(service.recentSearchesLimitLabel, 'Custom (75)');
    });

    test('clamps saved custom limit to valid range [5, 500]', () async {
      SharedPreferences.setMockInitialValues({
        SearchSettingsService.recentSearchesIsCustomKey: true,
        SearchSettingsService.recentSearchesLimitKey: 2,
      });
      await initializeSharedPrefs();
      service.resetForTesting();
      service.initialize();
      expect(service.recentSearchesLimit, 5);

      SharedPreferences.setMockInitialValues({
        SearchSettingsService.recentSearchesIsCustomKey: true,
        SearchSettingsService.recentSearchesLimitKey: 999,
      });
      await initializeSharedPrefs();
      service.resetForTesting();
      service.initialize();
      expect(service.recentSearchesLimit, 500);
    });

    test('setRecentSearchesLimit updates and persists custom limit', () async {
      service.initialize();
      await service.setRecentSearchesLimit(isCustom: true, customLimit: 50);

      expect(service.isCustomRecentLimit, isTrue);
      expect(service.customRecentLimit, 50);
      expect(service.recentSearchesLimit, 50);
      expect(service.recentSearchesLimitLabel, 'Custom (50)');
      expect(
        sharedPrefs.getBool(SearchSettingsService.recentSearchesIsCustomKey),
        isTrue,
      );
      expect(
        sharedPrefs.getInt(SearchSettingsService.recentSearchesLimitKey),
        50,
      );
    });

    test('setRecentSearchesLimit trims stored recent songs if limit is reduced', () async {
      // Store 10 songs in SharedPreferences
      final fakeSongs = List.generate(10, (i) => '{"id":"s$i","title":"Song $i","artist":"A","duration":100}');
      SharedPreferences.setMockInitialValues({
        SearchSettingsService.recentSongsKey: fakeSongs,
      });
      await initializeSharedPrefs();
      service.resetForTesting();
      service.initialize();

      // Reduce limit to 5
      await service.setRecentSearchesLimit(isCustom: true, customLimit: 5);

      final trimmed = sharedPrefs.getStringList(SearchSettingsService.recentSongsKey);
      expect(trimmed, isNotNull);
      expect(trimmed!.length, 5);
      expect(trimmed.first, contains('"s0"'));
      expect(trimmed.last, contains('"s4"'));
    });

    test('switching back to Standard restores limit 30', () async {
      service.initialize();
      await service.setRecentSearchesLimit(isCustom: true, customLimit: 100);
      expect(service.recentSearchesLimit, 100);

      await service.setRecentSearchesLimit(isCustom: false);
      expect(service.isCustomRecentLimit, isFalse);
      expect(service.recentSearchesLimit, 30);
      expect(service.recentSearchesLimitLabel, 'Standard (30)');
      // Preserves the configured custom limit in customRecentLimit
      expect(service.customRecentLimit, 100);
    });

    test('notifies listeners on limit change', () async {
      service.initialize();
      var count = 0;
      service.addListener(() => count++);

      await service.setRecentSearchesLimit(isCustom: true, customLimit: 40);
      expect(count, 1);

      // Idempotent call should not notify
      await service.setRecentSearchesLimit(isCustom: true, customLimit: 40);
      expect(count, 1);

      await service.setRecentSearchesLimit(isCustom: false);
      expect(count, 2);
    });

    test('setRecentSearchesLimit clamps customLimit to [5, 500]', () async {
      service.initialize();

      await service.setRecentSearchesLimit(isCustom: true, customLimit: 1);
      expect(service.customRecentLimit, 5);
      expect(service.recentSearchesLimit, 5);

      await service.setRecentSearchesLimit(isCustom: true, customLimit: 9999);
      expect(service.customRecentLimit, 500);
      expect(service.recentSearchesLimit, 500);
    });
  });
}
