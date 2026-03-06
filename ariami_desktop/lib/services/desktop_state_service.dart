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
}