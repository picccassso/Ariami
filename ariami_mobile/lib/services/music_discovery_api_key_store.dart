import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef LegacyMusicDiscoveryApiKeyReader = Future<String?> Function();

/// Stores the public Last.fm application key without using credential UI.
/// Actual secrets and session tokens remain in secure storage elsewhere.
class MusicDiscoveryApiKeyStore {
  const MusicDiscoveryApiKeyStore();

  static const key = 'ariami_lastfm_api_key_v1';
  static const _migrationAttemptedKey =
      'mobile_music_discovery_secure_storage_migration_v1';
  static const _householdKeyPrefix = 'ariami_lastfm_household_api_key_v1_';

  Future<String?> readAndMigrate(
    SharedPreferences preferences, {
    required LegacyMusicDiscoveryApiKeyReader readLegacyKey,
  }) async {
    final localKey = _readKey(preferences, key);
    if (localKey != null) return localKey;
    if (preferences.getBool(_migrationAttemptedKey) ?? false) return null;
    await preferences.setBool(_migrationAttemptedKey, true);

    try {
      final legacyKey = (await readLegacyKey())?.trim();
      if (legacyKey == null || legacyKey.isEmpty) return null;
      await preferences.setString(key, legacyKey);
      return legacyKey;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(SharedPreferences preferences, String value) async {
    await preferences.setBool(_migrationAttemptedKey, true);
    await preferences.setString(key, value.trim());
  }

  Future<String?> readHouseholdCache(
    SharedPreferences preferences,
    String scope,
  ) async {
    return _readKey(preferences, _householdCacheKey(scope));
  }

  Future<void> writeHouseholdCache(
    SharedPreferences preferences,
    String scope,
    String value,
  ) async {
    await preferences.setString(_householdCacheKey(scope), value.trim());
  }

  Future<void> deleteHouseholdCache(
    SharedPreferences preferences,
    String scope,
  ) async {
    await preferences.remove(_householdCacheKey(scope));
  }

  static String? _readKey(SharedPreferences preferences, String storageKey) {
    final value = preferences.getString(storageKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _householdCacheKey(String scope) =>
      '$_householdKeyPrefix${base64Url.encode(utf8.encode(scope))}';
}
