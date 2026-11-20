import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef LegacyMusicDiscoveryApiKeyReader = Future<String?> Function();

/// Stores the Last.fm API key locally without involving the OS credential UI.
///
/// Last.fm's API key is a public application identifier sent with requests;
/// Ariami never asks for or stores the separate API secret. Session tokens and
/// other credentials continue to use secure credential storage elsewhere.
class MusicDiscoveryApiKeyStore {
  const MusicDiscoveryApiKeyStore();

  static const key = 'ariami_lastfm_api_key_v1';
  static const _householdKeyPrefix = 'ariami_lastfm_household_api_key_v1_';
  static const _migrationAttemptedKey =
      'desktop_music_discovery_keychain_migration_v1';

  Future<String?> readAndMigrate(
    SharedPreferences preferences, {
    required LegacyMusicDiscoveryApiKeyReader readLegacyKey,
  }) async {
    final localKey = _read(preferences);
    if (localKey != null) return localKey;

    // Mark this before touching Keychain. If access is declined, opening
    // Discovery again must not produce the same macOS password prompt.
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
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await delete(preferences);
      return;
    }
    await preferences.setString(key, trimmed);
  }

  Future<void> delete(SharedPreferences preferences) async {
    // Keep the migration marker so disabling Discovery cannot resurrect a
    // legacy Keychain copy (and its password prompt) on the next open.
    await preferences.remove(key);
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
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await deleteHouseholdCache(preferences, scope);
      return;
    }
    await preferences.setString(_householdCacheKey(scope), trimmed);
  }

  Future<void> deleteHouseholdCache(
    SharedPreferences preferences,
    String scope,
  ) async {
    await preferences.remove(_householdCacheKey(scope));
  }

  static String? _read(SharedPreferences preferences) {
    return _readKey(preferences, key);
  }

  static String? _readKey(SharedPreferences preferences, String storageKey) {
    final value = preferences.getString(storageKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _householdCacheKey(String scope) =>
      '$_householdKeyPrefix${base64Url.encode(utf8.encode(scope))}';
}
