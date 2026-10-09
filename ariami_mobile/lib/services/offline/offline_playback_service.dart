import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/connection_service.dart';
import '../download/download_manager.dart';
import '../cache/cache_manager.dart';
import '../quality/quality_settings_service.dart';
import 'offline_copy_service.dart';

enum OfflineMode {
  online, // Connected to server, streaming available
  manualOffline, // User explicitly disabled connection (no auto-reconnect)
  autoOffline, // Connection lost, auto-reconnect attempts ongoing
}

enum PlaybackSource {
  stream, // Stream from server
  local, // Play from explicitly downloaded file (protected)
  cached, // Play from cached file (may be evicted)
  unavailable, // Song not available (offline and not downloaded/cached)
}

class OfflinePlaybackService {
  static final OfflinePlaybackService _instance =
      OfflinePlaybackService._internal();
  factory OfflinePlaybackService() => _instance;
  OfflinePlaybackService._internal();

  final ConnectionService _connectionService = ConnectionService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  final QualitySettingsService _qualityService = QualitySettingsService();
  final OfflineCopyService _offlineCopyService = OfflineCopyService();

  OfflineMode _offlineMode = OfflineMode.online;
  bool _preferDownloaded = true;
  bool _isInitialized = false;

  final StreamController<OfflineMode> _offlineStateController =
      StreamController<OfflineMode>.broadcast();

  Stream<OfflineMode> get offlineModeStream => _offlineStateController.stream;

  OfflineMode get offlineMode => _offlineMode;

  bool get isOfflineModeEnabled => _offlineMode != OfflineMode.online;

  /// Whether manual offline mode is enabled (user choice, no auto-reconnect)
  bool get isManualOfflineModeEnabled =>
      _offlineMode == OfflineMode.manualOffline;

  bool get preferDownloaded => _preferDownloaded;

  bool get isOffline => _offlineMode != OfflineMode.online;

  Future<void> initialize() async {
    if (_isInitialized) {
      print('[OfflinePlaybackService] Already initialized - skipping');
      return;
    }
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();
    await _offlineCopyService.initialize();

    final wasManualOffline = prefs.getBool('manual_offline_mode') ?? false;
    if (wasManualOffline) {
      _offlineMode = OfflineMode.manualOffline;
      print(
          '[OfflinePlaybackService] Restored manual offline mode from preferences');
    } else {
      _offlineMode = OfflineMode.online;
    }

    _preferDownloaded = prefs.getBool('prefer_downloaded') ?? true;

    _connectionService.connectionStateStream.listen((isConnected) {
      if (_offlineMode != OfflineMode.manualOffline) {
        if (!isConnected && _offlineMode == OfflineMode.online) {
          _setMode(OfflineMode.autoOffline);
        } else if (isConnected && _offlineMode == OfflineMode.autoOffline) {
          _setMode(OfflineMode.online);
        }
      }

      _offlineStateController.add(_offlineMode);
    });

    print('[OfflinePlaybackService] Initialized - Mode: $_offlineMode');
  }

  /// Enable manual offline mode (user toggle)
  /// Tells ConnectionService to disconnect fully
  Future<void> setManualOfflineMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (enabled) {
      await prefs.setBool('manual_offline_mode', true);
      _setMode(OfflineMode.manualOffline);
      print('[OfflinePlaybackService] Manual offline mode enabled (persisted)');
    } else {
      await prefs.remove('manual_offline_mode');
      print(
          '[OfflinePlaybackService] Manual offline mode disabled - attempting reconnect');

      // Transition to online optimistically (ConnectionService will handle reconnect)
      _setMode(OfflineMode.online);
    }
  }

  void _setMode(OfflineMode mode) {
    _offlineMode = mode;
    _offlineStateController.add(mode);
  }

  /// Called by ConnectionService when connection is automatically lost
  /// Only transitions if not in manual offline mode
  Future<void> notifyConnectionLost() async {
    if (_offlineMode != OfflineMode.manualOffline) {
      _setMode(OfflineMode.autoOffline);
      print(
          '[OfflinePlaybackService] Auto offline mode enabled (connection lost)');
    }
  }

  /// Called by ConnectionService when connection is successfully established.
  /// Transitions to online from any offline state (auto or manual).
  Future<void> notifyConnectionRestored() async {
    if (_offlineMode != OfflineMode.online) {
      _setMode(OfflineMode.online);
      print(
          '[OfflinePlaybackService] Online mode restored (connection regained)');
    }
  }

  Future<void> setPreferDownloaded(bool prefer) async {
    _preferDownloaded = prefer;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prefer_downloaded', prefer);

    print('[OfflinePlaybackService] Prefer downloaded: $prefer');
  }

  Future<PlaybackSource> getPlaybackSource(String songId) async {
    final isDownloaded = await _downloadManager.isSongDownloaded(songId);
    final isCached = await _cacheManager.isSongCached(songId);

    if (isDownloaded && _offlineCopyService.isRetainedSong(songId)) {
      return PlaybackSource.local;
    }

    if (isOffline) {
      // Offline mode - can only play downloaded or cached songs
      if (isDownloaded) {
        return PlaybackSource.local;
      } else if (isCached) {
        return PlaybackSource.cached;
      } else {
        return PlaybackSource.unavailable;
      }
    } else {
      // Online mode - stream by default to respect quality settings
      if (_qualityService.getPreferLocalWhenOnline()) {
        if (isDownloaded) {
          return PlaybackSource.local;
        } else if (isCached) {
          return PlaybackSource.cached;
        }
      }
      return PlaybackSource.stream;
    }
  }

  /// Source selection restricted to on-device copies, ignoring connection
  /// state. Used when a stream stalls on a dead-but-undetected network and
  /// playback falls back to the downloaded/cached file.
  Future<PlaybackSource> getOfflineFallbackSource(String songId) async {
    if (await _downloadManager.isSongDownloaded(songId)) {
      return PlaybackSource.local;
    }
    if (await _cacheManager.isSongCached(songId)) {
      return PlaybackSource.cached;
    }
    return PlaybackSource.unavailable;
  }

  String? getLocalFilePath(String songId) {
    return _downloadManager.getDownloadedSongPath(songId);
  }

  Future<String?> getCachedFilePath(String songId) async {
    return await _cacheManager.getCachedSongPath(songId);
  }

  Future<bool> isSongDownloaded(String songId) async {
    return await _downloadManager.isSongDownloaded(songId);
  }

  Future<bool> isSongCached(String songId) async {
    return await _cacheManager.isSongCached(songId);
  }

  Future<bool> isSongAvailableOffline(String songId) async {
    final isDownloaded = await _downloadManager.isSongDownloaded(songId);
    if (isDownloaded) return true;
    final isCached = await _cacheManager.isSongCached(songId);
    return isCached;
  }

  bool checkConnectivity() {
    return _connectionService.isConnected;
  }

  Stream<bool> get connectionStateStream =>
      _connectionService.connectionStateStream;

  void resetToDefaults() {
    _offlineMode = OfflineMode.online;
    _preferDownloaded = true;
    _offlineStateController.add(_offlineMode);
  }

  void dispose() {
    _offlineStateController.close();
  }
}
