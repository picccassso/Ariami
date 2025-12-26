import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/connection_service.dart';
import '../download/download_manager.dart';
import '../cache/cache_manager.dart';

/// Offline mode types
enum OfflineMode {
  online,          // Connected to server, streaming available
  manualOffline,   // User explicitly disabled connection (no auto-reconnect)
  autoOffline,     // Connection lost, auto-reconnect attempts ongoing
}

/// Playback source options
enum PlaybackSource {
  stream,      // Stream from server
  local,       // Play from explicitly downloaded file (protected)
  cached,      // Play from cached file (may be evicted)
  unavailable, // Song not available (offline and not downloaded/cached)
}

/// Service for managing offline playback functionality
class OfflinePlaybackService {
  // Singleton pattern
  static final OfflinePlaybackService _instance = OfflinePlaybackService._internal();
  factory OfflinePlaybackService() => _instance;
  OfflinePlaybackService._internal();

  final ConnectionService _connectionService = ConnectionService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();

  // Offline mode state
  OfflineMode _offlineMode = OfflineMode.online;
  bool _preferDownloaded = true;
  bool _isInitialized = false;

  // Stream controller for offline state changes
  final StreamController<OfflineMode> _offlineStateController =
      StreamController<OfflineMode>.broadcast();

  /// Stream of offline mode changes
  Stream<OfflineMode> get offlineModeStream => _offlineStateController.stream;

  /// Current offline mode
  OfflineMode get offlineMode => _offlineMode;

  /// Whether offline mode is currently enabled (manual or auto)
  bool get isOfflineModeEnabled => _offlineMode != OfflineMode.online;

  /// Whether manual offline mode is enabled (user choice, no auto-reconnect)
  bool get isManualOfflineModeEnabled => _offlineMode == OfflineMode.manualOffline;

  /// Whether to prefer downloaded files over streaming
  bool get preferDownloaded => _preferDownloaded;

  /// Check if currently offline (manual or auto)
  bool get isOffline => _offlineMode != OfflineMode.online;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize the service and load saved settings
  Future<void> initialize() async {
    // Only initialize once - subsequent calls are no-ops
    if (_isInitialized) {
      print('[OfflinePlaybackService] Already initialized - skipping');
      return;
    }
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();

    // Don't persist manual offline mode across app restarts
    // Always start in online mode and let connection attempts determine state
    _offlineMode = OfflineMode.online;

    _preferDownloaded = prefs.getBool('prefer_downloaded') ?? true;

    // Listen to connection state changes (auto offline handling)
    _connectionService.connectionStateStream.listen((isConnected) {
      // Only auto-transition if not in manual offline mode
      if (_offlineMode != OfflineMode.manualOffline) {
        if (!isConnected && _offlineMode == OfflineMode.online) {
          // Connection lost - auto offline
          _setMode(OfflineMode.autoOffline);
        } else if (isConnected && _offlineMode == OfflineMode.autoOffline) {
          // Connection restored - back to online
          _setMode(OfflineMode.online);
        }
      }

      _offlineStateController.add(_offlineMode);
    });

    print('[OfflinePlaybackService] Initialized - Mode: $_offlineMode');
  }

  // ============================================================================
  // OFFLINE MODE CONTROL
  // ============================================================================

  /// Enable manual offline mode (user toggle)
  /// Tells ConnectionService to disconnect fully
  Future<void> setManualOfflineMode(bool enabled) async {
    if (enabled) {
      // User wants to go offline manually
      _setMode(OfflineMode.manualOffline);
      print('[OfflinePlaybackService] Manual offline mode enabled');
    } else {
      // User wants to go back online - attempt reconnect
      print('[OfflinePlaybackService] Manual offline mode disabled - attempting reconnect');

      // Transition to online optimistically (ConnectionService will handle reconnect)
      _setMode(OfflineMode.online);
    }
  }

  /// Internal method to set mode and broadcast
  void _setMode(OfflineMode mode) {
    _offlineMode = mode;
    _offlineStateController.add(mode);
  }

  /// Called by ConnectionService when connection is automatically lost
  /// Only transitions if not in manual offline mode
  Future<void> notifyConnectionLost() async {
    if (_offlineMode != OfflineMode.manualOffline) {
      _setMode(OfflineMode.autoOffline);
      print('[OfflinePlaybackService] Auto offline mode enabled (connection lost)');
    }
  }

  /// Called by ConnectionService when connection is automatically restored
  /// Only transitions if in auto offline mode
  Future<void> notifyConnectionRestored() async {
    if (_offlineMode == OfflineMode.autoOffline) {
      _setMode(OfflineMode.online);
      print('[OfflinePlaybackService] Online mode restored (connection regained)');
    }
  }

  /// Enable or disable offline mode
  @Deprecated('Use setManualOfflineMode() instead')
  Future<void> setOfflineMode(bool enabled) async {
    // Map to new API for backward compatibility
    await setManualOfflineMode(enabled);
  }

  /// Set preference for downloaded files
  Future<void> setPreferDownloaded(bool prefer) async {
    _preferDownloaded = prefer;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prefer_downloaded', prefer);

    print('[OfflinePlaybackService] Prefer downloaded: $prefer');
  }

  // ============================================================================
  // PLAYBACK SOURCE SELECTION
  // ============================================================================

  /// Determine the playback source for a song
  Future<PlaybackSource> getPlaybackSource(String songId) async {
    final isDownloaded = await _downloadManager.isSongDownloaded(songId);
    final isCached = await _cacheManager.isSongCached(songId);

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
      // Online mode - prefer downloaded/cached if setting enabled
      if (isDownloaded && _preferDownloaded) {
        return PlaybackSource.local;
      } else if (isCached && _preferDownloaded) {
        return PlaybackSource.cached;
      } else {
        return PlaybackSource.stream;
      }
    }
  }

  /// Get local file path for a downloaded song
  String? getLocalFilePath(String songId) {
    return _downloadManager.getDownloadedSongPath(songId);
  }

  /// Get cached file path for a cached song
  Future<String?> getCachedFilePath(String songId) async {
    return await _cacheManager.getCachedSongPath(songId);
  }

  /// Check if a song is available for playback
  Future<bool> isSongAvailable(String songId) async {
    final source = await getPlaybackSource(songId);
    return source != PlaybackSource.unavailable;
  }

  /// Check if a song is downloaded (explicitly)
  Future<bool> isSongDownloaded(String songId) async {
    return await _downloadManager.isSongDownloaded(songId);
  }

  /// Check if a song is cached (auto-cached from playback)
  Future<bool> isSongCached(String songId) async {
    return await _cacheManager.isSongCached(songId);
  }

  /// Check if a song is available offline (downloaded OR cached)
  Future<bool> isSongAvailableOffline(String songId) async {
    final isDownloaded = await _downloadManager.isSongDownloaded(songId);
    if (isDownloaded) return true;
    final isCached = await _cacheManager.isSongCached(songId);
    return isCached;
  }

  // ============================================================================
  // CONNECTIVITY CHECK
  // ============================================================================

  /// Check current connectivity status
  bool checkConnectivity() {
    return _connectionService.isConnected;
  }

  /// Get the connection state stream
  Stream<bool> get connectionStateStream => _connectionService.connectionStateStream;

  // ============================================================================
  // CLEANUP
  // ============================================================================

  /// Dispose resources
  void dispose() {
    _offlineStateController.close();
  }
}



