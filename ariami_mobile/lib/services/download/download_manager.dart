import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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

/// Active-slot ceiling while cooler downloads mode is enabled.
const int coolerModeMaxConcurrentDownloads = 2;

/// Duty-cycle rest inserted after each completed transfer while cooler
/// downloads mode is enabled.
const Duration coolerModeSlotRefillRest = Duration(milliseconds: 1500);

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
  Future<void>? _initFuture;
  String? _downloadPath;
  String? _lastKnownServerId;
  String? _lastKnownUserId;
  bool _isAppInForeground = true;
  bool _coolerDownloadsEnabled = false;

  /// Tail of the serialized artwork-caching worker; extraction jobs chain
  /// onto it so at most one embedded-art parse runs at a time.
  Future<void> _artworkWorkTail = Future.value();
  final QualitySettingsService _qualityService = QualitySettingsService();
  final NativeDownloadService _nativeDownloadService = NativeDownloadService();

  /// Stream of download progress updates
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Stream of queue updates
  Stream<List<DownloadTask>> get queueStream => _queueController.stream;

  /// Get current queue
  List<DownloadTask> get queue => _getScopedQueue();

  /// Re-compute and re-broadcast the scoped queue on [queueStream].
  ///
  /// The scoped queue depends on the current connection scope (server + user),
  /// which the queue itself does not emit on when it changes. A background
  /// reconnect attempt transiently sets the API client (and therefore the
  /// scope) before it fails, so the one-shot startup queue broadcast can be
  /// computed under the wrong scope and leave downloads looking unavailable
  /// until the next queue change or an app restart. Call this when the scope
  /// settles (connect/disconnect) so consumers refresh against the final scope.
  void refreshScopedQueueBroadcast() => _refreshScopedQueueBroadcastImpl();

  /// Authoritative count of downloads currently occupying a concurrency slot.
  int get activeDownloadCount => _activeDownloadCount;

  /// Tasks observed in pending/downloading/paused state during this app
  /// session. Used by the downloads screen to anchor "X / Y" totals so old
  /// library downloads don't inflate the denominator and the count stays
  /// stable when the screen is closed and reopened mid-batch.
  final Set<String> sessionTaskIds = <String>{};

  /// Check if initialized
  bool get isInitialized => _initialized;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize the download manager.
  ///
  /// Idempotent: concurrent or repeat callers (the startup warm-up and the
  /// library's lazy `_ensureInitialized`) share a single initialization so the
  /// database and queue are never loaded more than once.
  Future<void> initialize() => _initFuture ??= _initializeImpl();

  /// Update the maximum number of concurrent downloads (per device)
  void setMaxConcurrentDownloads(int maxConcurrent) =>
      _setMaxConcurrentDownloadsImpl(maxConcurrent);

  /// Update app foreground state so Android can choose the fastest safe backend.
  void setAppInForeground(bool isForeground) =>
      _setAppInForegroundImpl(isForeground);

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

  /// Hand active downloads to the native background backend (Android) so
  /// they continue after the app leaves the foreground. Returns the number
  /// of transfers handed off; 0 when native continuation is unavailable and
  /// the caller should fall back to pausing.
  Future<int> continueDownloadsInBackground() =>
      _continueDownloadsInBackgroundImpl();

  /// Whether any task in the current scope is downloading or queued.
  bool get hasActiveOrPendingDownloads {
    if (!_initialized) return false;
    return _getScopedQueue().any((task) =>
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.pending);
  }

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

  /// Remove unfinished downloads that no longer exist in the current library.
  Future<int> pruneOrphanedIncompleteDownloads(Set<String> validSongIds) =>
      _pruneOrphanedIncompleteDownloadsImpl(validSongIds);

  /// Relink completed downloads after path-derived server song IDs change.
  Future<int> relinkOrphanedCompletedDownloads({
    required List<SongModel> librarySongs,
    required List<AlbumModel> libraryAlbums,
  }) =>
      _relinkOrphanedCompletedDownloadsImpl(
        librarySongs: librarySongs,
        libraryAlbums: libraryAlbums,
      );

  /// Re-point completed downloads at their current album ID when the album
  /// identity changed but the song itself is unchanged.
  ///
  /// Album IDs are derived from album title+artist, so a server-side metadata
  /// normalization (e.g. stripping NUL terminators from tags) re-hashes every
  /// album ID. Song IDs (path-derived) are unaffected, so we match by song and
  /// adopt the song's current album ID — otherwise the download would be flagged
  /// as an orphaned "offline copy" even though it is still in the library.
  ///
  /// Returns the exact old -> new album ID pairs that were remapped, so callers
  /// can migrate other album-keyed state (pins, recents) consistently.
  Future<Map<String, String>> migrateDownloadAlbumIds({
    required List<SongModel> librarySongs,
    required List<AlbumModel> libraryAlbums,
  }) =>
      _migrateDownloadAlbumIdsImpl(
        librarySongs: librarySongs,
        libraryAlbums: libraryAlbums,
      );

  /// Refresh saved album metadata while an authoritative library snapshot is
  /// available, so offline copies retain the server's title and artist.
  Future<int> refreshDownloadAlbumMetadata({
    required List<AlbumModel> libraryAlbums,
  }) =>
      _refreshDownloadAlbumMetadataImpl(libraryAlbums: libraryAlbums);

  /// Clear all downloads
  Future<void> clearAllDownloads() => _clearAllDownloadsImpl();

  /// Delete all downloads for a specific album
  /// Pass null albumId to delete all "Singles" (songs without an album)
  Future<void> deleteAlbumDownloads(String? albumId) =>
      _deleteAlbumDownloadsImpl(albumId);

  /// Delete explicit downloads for the given songs.
  Future<void> deleteSongDownloads(Iterable<String> songIds) =>
      _deleteSongDownloadsImpl(songIds);

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

  /// Whether cooler downloads mode (fewer slots + rests between files) is on.
  bool getCoolerDownloads() => _coolerDownloadsEnabled;

  /// Toggle cooler downloads mode. Applies immediately: enabling lets active
  /// transfers finish and stops refilling slots above the cooler cap;
  /// disabling refills up to the server's advertised limit.
  Future<void> setCoolerDownloads(bool enabled) async {
    if (_coolerDownloadsEnabled == enabled) return;
    _coolerDownloadsEnabled = enabled;
    await _database.setCoolerDownloads(enabled);
    print('DownloadManager: Cooler downloads mode set to $enabled');
    if (_initialized && !enabled) {
      _fillDownloadSlots();
    }
  }

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
