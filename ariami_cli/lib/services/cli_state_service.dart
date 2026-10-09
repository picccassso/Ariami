import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Service for managing CLI configuration and state.
/// Stores config in ~/.ariami_cli/ (separate from the desktop apps) unless
/// ARIAMI_DATA_DIR is set, which overrides the location.
class CliStateService {
  static final CliStateService _instance = CliStateService._internal();
  factory CliStateService() => _instance;
  CliStateService._internal();

  static String getConfigDir() {
    final dataDir = Platform.environment['ARIAMI_DATA_DIR'];
    if (dataDir != null && dataDir.isNotEmpty) {
      return dataDir;
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return path.join(home, '.ariami_cli');
  }

  static String getConfigFilePath() {
    return path.join(getConfigDir(), 'config.json');
  }

  static String getPidFilePath() {
    return path.join(getConfigDir(), 'ariami.pid');
  }

  static String getServerStateFilePath() {
    return path.join(getConfigDir(), 'server.json');
  }

  static String getLogFilePath() {
    return path.join(getConfigDir(), 'server.log');
  }

  static String getUsersFilePath() {
    return path.join(getConfigDir(), 'users.json');
  }

  static String getSessionsFilePath() {
    return path.join(getConfigDir(), 'sessions.json');
  }

  static String getMusicDiscoveryConfigFilePath() {
    return path.join(getConfigDir(), 'music_discovery.json');
  }

  static String getMetadataCacheFilePath() {
    return path.join(getConfigDir(), 'metadata_cache.json');
  }

  /// Get the catalog database file path (mirrors LibraryManager derivation).
  static String getCatalogDbFilePath() {
    return path.join(getConfigDir(), 'catalog.db');
  }

  static String getArtworkCacheDirPath() {
    return path.join(getConfigDir(), 'artwork_cache');
  }

  static String getTranscodedCacheDirPath() {
    return path.join(getConfigDir(), 'transcoded_cache');
  }

  static String getAutostartLogFilePath() {
    return path.join(getConfigDir(), 'autostart.log');
  }

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

  Future<void> _writeConfig(Map<String, dynamic> config) async {
    await ensureConfigDir();
    final configFile = File(getConfigFilePath());

    final encoded = jsonEncode(config);
    await configFile.writeAsString(encoded);
  }

  /// Update a single field in the config file (read-modify-write, not atomic).
  Future<void> _updateConfigField(String key, dynamic value) async {
    final config = await _readConfig();
    config[key] = value;
    await _writeConfig(config);
  }

  Future<bool> isSetupComplete() async {
    final config = await _readConfig();
    final value = config['setup_completed'];
    return value == true;
  }

  Future<void> markSetupComplete() async {
    await _updateConfigField('setup_completed', true);
  }

  Future<String?> getMusicFolderPath() async {
    final config = await _readConfig();
    final path = config['music_folder_path'];
    return path is String ? path : null;
  }

  Future<void> setMusicFolderPath(String folderPath) async {
    await _updateConfigField('music_folder_path', folderPath);
  }

  Future<int?> getServerPort() async {
    final config = await _readConfig();
    final value = config['server_port'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  Future<void> setServerPort(int port) async {
    await _updateConfigField('server_port', port);
  }

  Future<String> getBindHost() async {
    final config = await _readConfig();
    final value = config['bind_host'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '0.0.0.0';
  }

  Future<void> setBindHost(String host) async {
    await _updateConfigField('bind_host', host);
  }

  Future<int?> getTranscodeSlotsOverride() async {
    final config = await _readConfig();
    final value = config['transcode_slots'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  /// Whether the pre-auth sign-in account picker (used by Ariami TV) is
  /// enabled. Off by default — while enabled, any device on the network can
  /// list this server's usernames — so owners opt in through the web
  /// dashboard's privacy switch, which persists an explicit on here.
  Future<bool> getPublicUserPickerEnabled() async {
    final config = await _readConfig();
    return config['public_user_picker'] == true;
  }

  Future<void> setPublicUserPickerEnabled(bool enabled) async {
    await _updateConfigField('public_user_picker', enabled);
  }

  /// Set or clear the transcode slots override in config.
  Future<void> setTranscodeSlotsOverride(int? slots) async {
    final config = await _readConfig();
    if (slots == null) {
      config.remove('transcode_slots');
    } else {
      config['transcode_slots'] = slots;
    }
    await _writeConfig(config);
  }

  /// Get user-configured display alias for the LAN IP
  Future<String?> getLanServerAlias() async {
    final config = await _readConfig();
    final alias = config['lan_server_alias'] ?? config['lanServerAlias'];
    return alias is String && alias.trim().isNotEmpty ? alias.trim() : null;
  }

  /// Get user-configured display alias for the Tailscale IP
  Future<String?> getTailscaleServerAlias() async {
    final config = await _readConfig();
    final alias =
        config['tailscale_server_alias'] ?? config['tailscaleServerAlias'];
    return alias is String && alias.trim().isNotEmpty ? alias.trim() : null;
  }

  Future<void> setEndpointAliases({
    String? lanAlias,
    String? tailscaleAlias,
  }) async {
    final config = await _readConfig();
    if (lanAlias != null && lanAlias.trim().isNotEmpty) {
      config['lan_server_alias'] = lanAlias.trim();
    } else {
      config.remove('lan_server_alias');
      config.remove('lanServerAlias');
    }

    if (tailscaleAlias != null && tailscaleAlias.trim().isNotEmpty) {
      config['tailscale_server_alias'] = tailscaleAlias.trim();
    } else {
      config.remove('tailscale_server_alias');
      config.remove('tailscaleServerAlias');
    }

    await _writeConfig(config);
  }

  Future<void> clearConfig() async {
    final configDir = Directory(getConfigDir());
    if (await configDir.exists()) {
      await configDir.delete(recursive: true);
    }
  }
}
