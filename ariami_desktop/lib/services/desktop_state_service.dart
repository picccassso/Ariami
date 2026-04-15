import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing desktop app state and setup completion
class DesktopStateService {
  // Singleton pattern
  static final DesktopStateService _instance = DesktopStateService._internal();
  factory DesktopStateService() => _instance;
  DesktopStateService._internal();

  static const String _setupCompleteKey = 'setup_completed';
  static const String _ownerSetupSkippedKey = 'owner_setup_skipped';

  /// Check if initial setup has been completed
  Future<bool> isSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupCompleteKey) ?? false;
  }

  /// Mark initial setup as complete
  Future<void> markSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupCompleteKey, true);
  }

  /// Clear setup state (for testing or reset)
  Future<void> clearSetupState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setupCompleteKey);
  }

  /// Whether the user explicitly skipped owner setup during onboarding.
  Future<bool> isOwnerSetupSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ownerSetupSkippedKey) ?? false;
  }

  /// Mark owner setup as skipped during onboarding.
  Future<void> markOwnerSetupSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ownerSetupSkippedKey, true);
  }

  /// Clear skipped-owner flag once owner setup is completed.
  Future<void> clearOwnerSetupSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ownerSetupSkippedKey);
  }

  // ============================================================================
  // AUTH FILE PATHS (for multi-user support)
  // ============================================================================

  /// Get the auth config directory path
  Future<String> getAuthConfigDir() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return appSupportDir.path;
  }

  /// Get the users file path (for multi-user auth)
  Future<String> getUsersFilePath() async {
    final configDir = await getAuthConfigDir();
    return path.join(configDir, 'users.json');
  }

  /// Get the sessions file path (for multi-user auth)
  Future<String> getSessionsFilePath() async {
    final configDir = await getAuthConfigDir();
    return path.join(configDir, 'sessions.json');
  }

  /// Ensure auth config directory exists
  Future<void> ensureAuthConfigDir() async {
    final configDir = Directory(await getAuthConfigDir());
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
  }

  /// Whether at least one account exists in users.json.
  Future<bool> hasOwnerAccount() async {
    final users = await _readUsersList();
    return users.isNotEmpty;
  }

  /// Owner username (the first created account), matching server logic.
  Future<String?> getOwnerUsername() async {
    final users = await _readUsersList();
    if (users.isEmpty) return null;

    users.sort((a, b) {
      final aCreatedAt = a['createdAt']?.toString() ?? '';
      final bCreatedAt = b['createdAt']?.toString() ?? '';
      final createdCompare = aCreatedAt.compareTo(bCreatedAt);
      if (createdCompare != 0) return createdCompare;

      final aUserId = a['userId']?.toString() ?? '';
      final bUserId = b['userId']?.toString() ?? '';
      return aUserId.compareTo(bUserId);
    });

    final username = users.first['username']?.toString();
    if (username == null || username.isEmpty) return null;
    return username;
  }

  Future<List<Map<String, dynamic>>> _readUsersList() async {
    try {
      final usersPath = await getUsersFilePath();
      final file = File(usersPath);
      if (!await file.exists()) return const [];

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final users = decoded['users'];
      if (users is! List) return const [];

      return users
          .whereType<Map>()
          .map(
              (entry) => entry.map((key, value) => MapEntry('$key', value)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}