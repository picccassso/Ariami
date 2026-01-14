import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Service for managing CLI configuration and state
/// Stores config in ~/.ariami_cli/ directory (separate from ariami_desktop)
class CliStateService {
  // Singleton pattern
  static final CliStateService _instance = CliStateService._internal();
  factory CliStateService() => _instance;
  CliStateService._internal();

  /// Get the config directory path
  static String getConfigDir() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return path.join(home, '.ariami_cli');
  }

  /// Get the config file path
  static String getConfigFilePath() {
    return path.join(getConfigDir(), 'config.json');
  }

  /// Get the PID file path
  static String getPidFilePath() {
    return path.join(getConfigDir(), 'ariami.pid');
  }

  /// Get the server state file path
  static String getServerStateFilePath() {
    return path.join(getConfigDir(), 'server.json');
  }

  /// Get the server log file path
  static String getLogFilePath() {
    return path.join(getConfigDir(), 'server.log');
  }

  /// Ensure config directory exists
  Future<void> ensureConfigDir() async {
    final configDir = Directory(getConfigDir());
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
  }

  /// Read the entire config file as a Map
  /// Returns empty Map if file doesn't exist or is invalid
  Future<Map<String, dynamic>> _readConfig() async {
    await ensureConfigDir();
    final configFile = File(getConfigFilePath());

    if (!await configFile.exists()) {
      return {};
    }

    try {
      final content = await configFile.readAsString();
      if (content.isEmpty) {
        return {};
      }

      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {};
    } catch (e) {
      return {};
    }
  }

  /// Write the entire config file from a Map
  Future<void> _writeConfig(Map<String, dynamic> config) async {
    await ensureConfigDir();
    final configFile = File(getConfigFilePath());

    final encoded = jsonEncode(config);
    await configFile.writeAsString(encoded);
  }

  /// Update a single field in the config file (atomic operation)
  Future<void> _updateConfigField(String key, dynamic value) async {
    final config = await _readConfig();
    config[key] = value;
    await _writeConfig(config);
  }

  /// Check if setup is complete
  Future<bool> isSetupComplete() async {
    final config = await _readConfig();
    final value = config['setup_completed'];
    return value == true;
  }

  /// Mark setup as complete
  Future<void> markSetupComplete() async {
    await _updateConfigField('setup_completed', true);
  }

  /// Get music folder path from config
  Future<String?> getMusicFolderPath() async {
    final config = await _readConfig();
    final path = config['music_folder_path'];
    return path is String ? path : null;
  }

  /// Set music folder path in config
  Future<void> setMusicFolderPath(String folderPath) async {
    await _updateConfigField('music_folder_path', folderPath);
  }

  /// Clear all configuration
  Future<void> clearConfig() async {
    final configDir = Directory(getConfigDir());
    if (await configDir.exists()) {
      await configDir.delete(recursive: true);
    }
  }
}
