import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';

/// Database layer for managing downloads persistence
class DownloadDatabase {
  static const String _downloadQueueKey = 'download_queue';

  final SharedPreferences _prefs;

  DownloadDatabase(this._prefs);

  /// Create instance from platform
  static Future<DownloadDatabase> create() async {
    final prefs = await SharedPreferences.getInstance();
    return DownloadDatabase(prefs);
  }

  // ============================================================================
  // QUEUE MANAGEMENT
  // ============================================================================

  /// Save all download tasks to storage
  Future<void> saveDownloadQueue(List<DownloadTask> tasks) async {
    final jsonList = tasks.map((task) => jsonEncode(task.toJson())).toList();
    await _prefs.setStringList(_downloadQueueKey, jsonList);
  }

  /// Load all download tasks from storage
  Future<List<DownloadTask>> loadDownloadQueue() async {
    final jsonList = _prefs.getStringList(_downloadQueueKey) ?? [];
    return jsonList
        .map((json) => DownloadTask.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
  }

  /// Clear all downloads from queue
  Future<void> clearDownloadQueue() async {
    await _prefs.remove(_downloadQueueKey);
  }

  // ============================================================================
  // DOWNLOAD SETTINGS
  // ============================================================================

  /// Set WiFi-only download toggle
  Future<void> setWifiOnly(bool wifiOnly) async {
    await _prefs.setBool('download_wifi_only', wifiOnly);
  }

  /// Get WiFi-only setting
  bool getWifiOnly() {
    return _prefs.getBool('download_wifi_only') ?? true;
  }

  /// Set auto-download favorites toggle
  Future<void> setAutoDownloadFavorites(bool auto) async {
    await _prefs.setBool('download_auto_favorites', auto);
  }

  /// Get auto-download setting
  bool getAutoDownloadFavorites() {
    return _prefs.getBool('download_auto_favorites') ?? false;
  }

  /// Set storage limit in MB (null = unlimited)
  Future<void> setStorageLimit(int? limitMB) async {
    if (limitMB == null) {
      await _prefs.remove('download_storage_limit');
    } else {
      await _prefs.setInt('download_storage_limit', limitMB);
    }
  }

  /// Get storage limit in MB
  int? getStorageLimit() {
    return _prefs.getInt('download_storage_limit');
  }

  // ============================================================================
  // USAGE TRACKING
  // ============================================================================

  /// Get total bytes used for downloads
  int getTotalDownloadBytes() {
    final queue = _prefs.getStringList(_downloadQueueKey) ?? [];
    int total = 0;

    for (final json in queue) {
      final task = DownloadTask.fromJson(jsonDecode(json) as Map<String, dynamic>);
      if (task.status == DownloadStatus.completed) {
        total += task.bytesDownloaded;
      }
    }

    return total;
  }

  /// Get number of completed downloads
  int getCompletedDownloadCount() {
    final queue = _prefs.getStringList(_downloadQueueKey) ?? [];
    int count = 0;

    for (final json in queue) {
      final task = DownloadTask.fromJson(jsonDecode(json) as Map<String, dynamic>);
      if (task.status == DownloadStatus.completed) {
        count++;
      }
    }

    return count;
  }

  /// Get total download size in MB
  double getTotalDownloadSizeMB() {
    return getTotalDownloadBytes() / (1024 * 1024);
  }

  /// Clear all download data including settings
  Future<void> clearAllDownloads() async {
    await _prefs.remove(_downloadQueueKey);
    // Keep settings, just clear the queue
  }
}
