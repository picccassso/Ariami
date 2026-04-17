import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists library pinned items with per-user isolation.
class LibraryPinStorage {
  static const String legacyKey = 'library_pinned_items';

  static String keyForUser(String? userId) {
    final normalized = userId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return legacyKey;
    }
    return '${legacyKey}_$normalized';
  }

  static Future<Set<String>> loadForUser(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(keyForUser(userId));
    if (jsonString == null || jsonString.isEmpty) {
      return <String>{};
    }

    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> saveForUser(
    String? userId,
    Set<String> pinnedItemIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyForUser(userId),
      jsonEncode(pinnedItemIds.toList()),
    );
  }

  /// One-time migration path from legacy global pins to the logging-out user.
  static Future<void> migrateLegacyPinsToUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final scopedKey = keyForUser(normalized);
    if (prefs.containsKey(scopedKey)) {
      return;
    }

    final legacyJson = prefs.getString(legacyKey);
    if (legacyJson == null || legacyJson.isEmpty) {
      return;
    }

    await prefs.setString(scopedKey, legacyJson);
    await prefs.remove(legacyKey);
  }
}
