import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/api_models.dart';
import '../../database/download_database.dart';
import '../../models/download_task.dart';
import '../../models/quality_settings.dart';
import '../api/api_client.dart';
import '../api/connection_service.dart';
import '../cache/cache_manager.dart';
import '../quality/quality_settings_service.dart';
import 'download_queue.dart';
import 'local_artwork_extractor.dart';
import 'download_helpers.dart';
import 'native_download_service.dart';

part 'download_manager_initialization_impl.dart';
part 'download_manager_operations_impl.dart';
part 'download_manager_transfer_impl.dart';
part 'download_manager_maintenance_impl.dart';

/// Manages all download operations
class DownloadManager {
  // Singleton pattern
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  late DownloadDatabase _database;
  late Dio _dio;

  final DownloadQueue _queue = DownloadQueue();
  final Map<String, CancelToken> _activeDownloads = {};
  final Map<String, double> _activeProgress =
      {}; // Track progress separately to avoid queue updates
  int _activeDownloadCount = 0; // Track number of concurrent downloads
  int _maxConcurrentDownloads = 10; // Max concurrent downloads allowed
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  final StreamController<List<DownloadTask>> _queueController =
      StreamController<List<DownloadTask>>.broadcast();
  final math.Random _retryRandom = math.Random();
  final Map<String, String> _persistedTaskSignatures = {};
  List<DownloadTask>? _pendingPersistenceSnapshot;
  bool _persistenceInFlight = false;
  List<DownloadTask>? _scopedQueueCache;
  String? _scopedQueueCacheServerId;
  String? _scopedQueueCacheUserId;
  StreamSubscription<bool>? _connectionStateSubscription;

  bool _initialized = false;
  String? _downloadPath;
  String? _lastKnownServerId;
  String? _lastKnownUserId;
  final QualitySettingsService _qualityService = QualitySettingsService();
  final NativeDownloadService _nativeDownloadService = NativeDownloadService();

  /// Stream of download progress updates
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Stream of queue updates
  Stream<List<DownloadTask>> get queueStream => _queueController.stream;

  /// Get current queue
  List<DownloadTask> get queue => _getScopedQueue();

  /// Check if initialized
  bool get isInitialized => _initialized;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize the download manager
  Future<void> initialize() => _initializeImpl();

  /// Update the maximum number of concurrent downloads (per device)
  void setMaxConcurrentDownloads(int maxConcurrent) =>
      _setMaxConcurrentDownloadsImpl(maxConcurrent);

  // ============================================================================
  // DOWNLOAD OPERATIONS
  // ============================================================================

  /// Create a server-managed download job and enqueue its items page-by-page.
  ///
  /// Used by "Download All" flows to avoid client-side enqueue storms.
  Future<int> enqueueDownloadJob({
    List<String> songIds = const <String>[],
    List<String> albumIds = const <String>[],
    List<String> playlistIds = const <String>[],
    StreamingQuality? downloadQuality,
    bool? downloadOriginal,
  }) =>
      _enqueueDownloadJobImpl(
        songIds: songIds,
        albumIds: albumIds,
        playlistIds: playlistIds,
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );

  /// Download a single song
  Future<void> downloadSong({
    required String songId,
    required String title,
    required String artist,
    String? albumId,
    String? albumName,
    String? albumArtist,
    required String albumArt,
    StreamingQuality? downloadQuality,
    bool? downloadOriginal,
    int duration = 0,
    int? trackNumber,
    required int totalBytes,
  }) =>
      _downloadSongImpl(
        songId: songId,
        title: title,
        artist: artist,
        albumId: albumId,
        albumName: albumName,
        albumArtist: albumArtist,
        albumArt: albumArt,
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
        duration: duration,
        trackNumber: trackNumber,
        totalBytes: totalBytes,
      );

  /// Download entire album
  Future<void> downloadAlbum({
    required List<Map<String, dynamic>> songs,
    String? albumId,
    String? albumName,
    String? albumArtist,
    StreamingQuality? downloadQuality,
    bool? downloadOriginal,
  }) =>
      _downloadAlbumImpl(
        songs: songs,
        albumId: albumId,
        albumName: albumName,
        albumArtist: albumArtist,
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );

  /// Pause a download
  void pauseDownload(String taskId) => _pauseDownloadImpl(taskId);

  /// Resume a paused download
  Future<void> resumeDownload(String taskId) => _resumeDownloadImpl(taskId);

  /// Resume all interrupted (auto-paused) downloads in the current scope.
  Future<int> resumeInterruptedDownloads() => _resumeInterruptedDownloadsImpl();

  /// Resume downloads paused by a foreground lifecycle interruption.
  Future<int> resumeLifecycleInterruptedDownloads() =>
      _resumeLifecycleInterruptedDownloadsImpl();

  /// Cancel all interrupted (auto-paused) downloads in the current scope.
  Future<int> cancelInterruptedDownloads() => _cancelInterruptedDownloadsImpl();

  /// Number of interrupted (auto-paused) downloads in the current scope.
  int getInterruptedDownloadCount() => _getInterruptedDownloadCountImpl();

  /// Pause active/pending downloads and flush queue state when app closes.
  Future<void> pauseDownloadsForAppClosure() =>
      _pauseDownloadsForAppClosureImpl();

  /// Pause active/pending downloads for a temporary app lifecycle interruption.
  Future<void> pauseDownloadsForLifecycleInterruption() =>
      _pauseDownloadsForLifecycleInterruptionImpl();

  /// Retry a failed download
  Future<void> retryDownload(String taskId) => _retryDownloadImpl(taskId);

  /// Cancel a download
  void cancelDownload(String taskId) => _cancelDownloadImpl(taskId);

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Check if a song is downloaded
  Future<bool> isSongDownloaded(String songId) => _isSongDownloadedImpl(songId);

  /// Get downloaded song file path
  String? getDownloadedSongPath(String songId) =>
      _getDownloadedSongPathImpl(songId);

  /// Get any downloaded local file path for a given album.
  /// Returns null when the album has no completed downloads.
  String? getAnyDownloadedSongPathForAlbum(String albumId) =>
      _getAnyDownloadedSongPathForAlbumImpl(albumId);

  /// Get total downloaded size in MB
  double getTotalDownloadedSizeMB() => _getTotalDownloadedSizeMBImpl();

  /// Get number of completed downloads
  int getCompletedDownloadCount() => _getCompletedDownloadCountImpl();

  /// Get queue statistics
  QueueStats getQueueStats() => _getQueueStatsImpl();

  /// Get current progress for a task (from active progress tracking)
  /// Returns null if task is not actively downloading
  double? getTaskProgress(String taskId) {
    return _activeProgress[taskId];
  }

  /// Remove downloads that no longer exist in the current library
  /// Returns the number of tasks removed.
  Future<int> pruneOrphanedDownloads(Set<String> validSongIds) =>
      _pruneOrphanedDownloadsImpl(validSongIds);

  /// Clear all downloads
  Future<void> clearAllDownloads() => _clearAllDownloadsImpl();

  /// Delete all downloads for a specific album
  /// Pass null albumId to delete all "Singles" (songs without an album)
  Future<void> deleteAlbumDownloads(String? albumId) =>
      _deleteAlbumDownloadsImpl(albumId);

  /// Get download settings
  bool getWifiOnly() => _database.getWifiOnly();

  bool getAutoDownloadFavorites() => _database.getAutoDownloadFavorites();

  int? getStorageLimit() => _database.getStorageLimit();

  bool getAutoResumeInterruptedOnLaunch() =>
      _database.getAutoResumeInterruptedOnLaunch();

  /// Set download settings
  Future<void> setWifiOnly(bool wifiOnly) => _database.setWifiOnly(wifiOnly);

  Future<void> setAutoDownloadFavorites(bool auto) =>
      _database.setAutoDownloadFavorites(auto);

  Future<void> setStorageLimit(int? limitMB) =>
      _database.setStorageLimit(limitMB);

  Future<void> setAutoResumeInterruptedOnLaunch(bool enabled) =>
      _database.setAutoResumeInterruptedOnLaunch(enabled);

  /// Dispose resources
  void dispose() {
    _connectionStateSubscription?.cancel();
    _progressController.close();
    _queueController.close();
    _queue.dispose();
  }
}

/// Download progress information
class DownloadProgress {
  final String taskId;
  final double progress; // 0.0 to 1.0
  final int bytesDownloaded;
  final int totalBytes;

  DownloadProgress({
    required this.taskId,
    required this.progress,
    required this.bytesDownloaded,
    required this.totalBytes,
  });

  int get percentage => (progress * 100).toInt();
}
