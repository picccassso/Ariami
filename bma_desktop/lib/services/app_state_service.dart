import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage desktop app-wide state and persistent data
/// Tracks setup completion, music folder path, and server preferences
class AppStateService extends ChangeNotifier {
  static const String _setupCompleteKey = 'setup_complete';
  static const String _musicFolderPathKey = 'music_folder_path';
  static const String _autoStartServerKey = 'auto_start_server';

  bool _setupComplete = false;
  String? _musicFolderPath;
  bool _autoStartServer = true; // Default to auto-start
  bool _isInitialized = false;

  // Getters
  bool get setupComplete => _setupComplete;
  String? get musicFolderPath => _musicFolderPath;
  bool get autoStartServer => _autoStartServer;
  bool get isInitialized => _isInitialized;

  /// Initialize the service by loading saved state
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      _setupComplete = prefs.getBool(_setupCompleteKey) ?? false;
      _musicFolderPath = prefs.getString(_musicFolderPathKey);
      _autoStartServer = prefs.getBool(_autoStartServerKey) ?? true;

      _isInitialized = true;
      notifyListeners();

      debugPrint('[AppStateService] Initialized - Setup complete: $_setupComplete');
      debugPrint('[AppStateService] Music folder: $_musicFolderPath');
      debugPrint('[AppStateService] Auto-start server: $_autoStartServer');
    } catch (e) {
      debugPrint('[AppStateService] Error initializing: $e');
      _isInitialized = true;
    }
  }

  /// Check if setup has been completed
  bool hasCompletedSetup() {
    return _setupComplete;
  }

  /// Check if music folder is configured and still exists
  Future<bool> isMusicFolderValid() async {
    if (_musicFolderPath == null) return false;

    try {
      final dir = Directory(_musicFolderPath!);
      return await dir.exists();
    } catch (e) {
      debugPrint('[AppStateService] Error checking music folder: $e');
      return false;
    }
  }

  /// Check if server should auto-start on app launch
  bool shouldAutoStartServer() {
    return _autoStartServer && _setupComplete;
  }

  /// Mark setup as complete
  Future<void> markSetupComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_setupCompleteKey, true);

      _setupComplete = true;
      notifyListeners();

      debugPrint('[AppStateService] Setup marked as complete');
    } catch (e) {
      debugPrint('[AppStateService] Error marking setup complete: $e');
    }
  }

  /// Save music folder path
  Future<void> saveMusicFolderPath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_musicFolderPathKey, path);

      _musicFolderPath = path;
      notifyListeners();

      debugPrint('[AppStateService] Saved music folder: $path');
    } catch (e) {
      debugPrint('[AppStateService] Error saving music folder: $e');
    }
  }

  /// Get music folder path
  String? getMusicFolderPath() {
    return _musicFolderPath;
  }

  /// Set auto-start server preference
  Future<void> setAutoStartServer(bool autoStart) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoStartServerKey, autoStart);

      _autoStartServer = autoStart;
      notifyListeners();

      debugPrint('[AppStateService] Auto-start server: $autoStart');
    } catch (e) {
      debugPrint('[AppStateService] Error setting auto-start: $e');
    }
  }

  /// Clear all app state (for debugging/reset)
  Future<void> clearAllState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_setupCompleteKey);
      await prefs.remove(_musicFolderPathKey);
      await prefs.remove(_autoStartServerKey);

      _setupComplete = false;
      _musicFolderPath = null;
      _autoStartServer = true;
      notifyListeners();

      debugPrint('[AppStateService] All state cleared');
    } catch (e) {
      debugPrint('[AppStateService] Error clearing state: $e');
    }
  }
}
