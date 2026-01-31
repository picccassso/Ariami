import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/quality_settings.dart';
import 'network_monitor_service.dart';

/// Service for managing audio quality settings
///
/// Handles persistence and provides the appropriate streaming quality
/// based on current network conditions (WiFi vs mobile data).
class QualitySettingsService {
  // Singleton pattern
  static final QualitySettingsService _instance =
      QualitySettingsService._internal();
  factory QualitySettingsService() => _instance;
  QualitySettingsService._internal();

  static const String _prefsKey = 'quality_settings';

  QualitySettings _settings = const QualitySettings();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();

  final _settingsController = StreamController<QualitySettings>.broadcast();

  /// Stream of settings changes
  Stream<QualitySettings> get settingsStream => _settingsController.stream;

  /// Current quality settings
  QualitySettings get settings => _settings;

  /// Initialize the service and load saved settings
  Future<void> initialize() async {
    await _loadSettings();
    await _networkMonitor.initialize();
    print('[QualitySettingsService] Initialized with settings: $_settings');
  }

  /// Load settings from persistent storage
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKey);

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        _settings = QualitySettings.fromJson(json);
      }
    } catch (e) {
      print('[QualitySettingsService] Error loading settings: $e');
      // Keep default settings on error
    }
  }

  /// Save settings to persistent storage
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_settings.toJson());
      await prefs.setString(_prefsKey, jsonString);
    } catch (e) {
      print('[QualitySettingsService] Error saving settings: $e');
    }
  }

  /// Update quality settings
  Future<void> updateSettings(QualitySettings newSettings) async {
    if (_settings == newSettings) return;

    _settings = newSettings;
    await _saveSettings();
    _settingsController.add(_settings);
    print('[QualitySettingsService] Settings updated: $_settings');
  }

  /// Update WiFi streaming quality
  Future<void> setWifiQuality(StreamingQuality quality) async {
    await updateSettings(_settings.copyWith(wifiQuality: quality));
  }

  /// Update mobile data streaming quality
  Future<void> setMobileDataQuality(StreamingQuality quality) async {
    await updateSettings(_settings.copyWith(mobileDataQuality: quality));
  }

  /// Update download quality
  Future<void> setDownloadQuality(StreamingQuality quality) async {
    await updateSettings(_settings.copyWith(downloadQuality: quality));
  }

  /// Update download mode (original vs transcoded)
  Future<void> setDownloadOriginal(bool downloadOriginal) async {
    await updateSettings(_settings.copyWith(downloadOriginal: downloadOriginal));
  }

  /// Get the current streaming quality based on network type
  ///
  /// Returns the appropriate quality setting based on whether
  /// the device is on WiFi or mobile data.
  StreamingQuality getCurrentStreamingQuality() {
    final networkType = _networkMonitor.currentNetworkType;

    switch (networkType) {
      case NetworkType.wifi:
        return _settings.wifiQuality;
      case NetworkType.mobile:
        return _settings.mobileDataQuality;
      case NetworkType.none:
        // Offline - use mobile quality (more conservative)
        return _settings.mobileDataQuality;
    }
  }

  /// Get the download quality setting
  StreamingQuality getDownloadQuality() {
    return _settings.downloadQuality;
  }

  /// Whether downloads should use the original file
  bool getDownloadOriginal() {
    return _settings.downloadOriginal;
  }

  /// Get stream URL with quality parameter
  ///
  /// Appends the appropriate quality parameter based on current network.
  String getStreamUrlWithQuality(String baseStreamUrl) {
    final quality = getCurrentStreamingQuality();

    // High quality doesn't need a parameter (server default)
    if (quality == StreamingQuality.high) {
      return baseStreamUrl;
    }

    // Add quality parameter
    final separator = baseStreamUrl.contains('?') ? '&' : '?';
    return '$baseStreamUrl${separator}quality=${quality.toApiParam()}';
  }

  /// Get download URL with quality parameter
  String getDownloadUrlWithQuality(String baseDownloadUrl) {
    if (_settings.downloadOriginal) {
      return baseDownloadUrl;
    }

    final quality = _settings.downloadQuality;

    // High quality doesn't need a parameter (server default)
    if (quality == StreamingQuality.high) {
      return baseDownloadUrl;
    }

    // Add quality parameter
    final separator = baseDownloadUrl.contains('?') ? '&' : '?';
    return '$baseDownloadUrl${separator}quality=${quality.toApiParam()}';
  }

  /// Stream of current network type changes
  Stream<NetworkType> get networkTypeStream => _networkMonitor.networkTypeStream;

  /// Current network type
  NetworkType get currentNetworkType => _networkMonitor.currentNetworkType;

  /// Dispose resources
  void dispose() {
    _settingsController.close();
    _networkMonitor.dispose();
  }
}
