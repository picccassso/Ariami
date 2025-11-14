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
}