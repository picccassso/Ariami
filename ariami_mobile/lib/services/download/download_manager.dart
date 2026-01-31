import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/download_database.dart';
import '../../models/download_task.dart';
import '../api/connection_service.dart';
import '../cache/cache_manager.dart';
import 'download_queue.dart';

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
  final Map<String, double> _activeProgress = {}; // Track progress separately to avoid queue updates
  int _activeDownloadCount = 0; // Track number of concurrent downloads
  static const int _maxConcurrentDownloads = 10; // Max concurrent downloads allowed
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  final StreamController<List<DownloadTask>> _queueController =
      StreamController<List<DownloadTask>>.broadcast();

  bool _initialized = false;
  String? _downloadPath;
  String? _lastKnownServerId;

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
  Future<void> initialize() async {
    if (_initialized) return;

    // Setup database
    _database = await DownloadDatabase.create();

    // Load queue from storage into the already-initialized _queue
    final savedQueue = await _database.loadDownloadQueue();
    for (final task in savedQueue) {
      _queue.enqueue(task);
    }

    // Setup HTTP client
    _dio = Dio();

    // Get download directory
    final appDir = await getApplicationDocumentsDirectory();
    _downloadPath = '${appDir.path}/downloads';
    await Directory(_downloadPath!).create(recursive: true);

    // Listen to queue changes and persist
    _queue.queueStream.listen((tasks) {
      _database.saveDownloadQueue(tasks);
      _ensureServerScope();
      _queueController.add(_filterTasksForCurrentServer(tasks));
    });

    _initialized = true;
    print('DownloadManager initialized');

    // Run one-time artwork backfill for existing downloads (non-blocking)
    _backfillArtworkForExistingDownloads();
  }

  /// Ensure initialization
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  String? _getCurrentServerId() {
    final apiClient = ConnectionService().apiClient;
    return apiClient?.baseUrl;
  }

  void _ensureServerScope() {
    final currentServerId = _getCurrentServerId();
    if (currentServerId == null) return;

    if (_lastKnownServerId != currentServerId) {
      _lastKnownServerId = currentServerId;
    }

    final tasks = List<DownloadTask>.from(_queue.queue);
    int updatedCount = 0;
    for (final task in tasks) {
      if (task.serverId == null) {
        task.serverId = currentServerId;
        _queue.updateTask(task);
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      print('DownloadManager: Scoped $updatedCount downloads to $currentServerId');
    }
  }

  List<DownloadTask> _filterTasksForCurrentServer(List<DownloadTask> tasks) {
    final currentServerId = _getCurrentServerId();
    if (currentServerId == null) {
      return List<DownloadTask>.from(tasks);
    }
    return tasks.where((task) => task.serverId == currentServerId).toList();
  }

  List<DownloadTask> _getScopedQueue() {
    _ensureServerScope();
    return _filterTasksForCurrentServer(_queue.queue);
  }

  QueueStats _buildQueueStats(List<DownloadTask> tasks) {
    int totalTasks = tasks.length;
    int completed = tasks.where((t) => t.status == DownloadStatus.completed).length;
    int downloading = tasks.where((t) => t.status == DownloadStatus.downloading).length;
    int failed = tasks.where((t) => t.status == DownloadStatus.failed).length;
    int paused = tasks.where((t) => t.status == DownloadStatus.paused).length;

    int totalBytes = 0;
    int downloadedBytes = 0;

    for (final task in tasks) {
      totalBytes += task.totalBytes;
      downloadedBytes += task.bytesDownloaded;
    }

    return QueueStats(
      totalTasks: totalTasks,
      completed: completed,
      downloading: downloading,
      failed: failed,
      paused: paused,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
    );
  }

  DownloadTask? _getScopedTask(String taskId) {
    _ensureServerScope();
    final currentServerId = _getCurrentServerId();
    for (final task in _queue.queue) {
      if (task.id != taskId) continue;
      if (currentServerId == null || task.serverId == currentServerId) {
        return task;
      }
    }
    return null;
  }

  // ============================================================================
  // DOWNLOAD OPERATIONS
  // ============================================================================

  /// Download a single song
  Future<void> downloadSong({
    required String songId,
    required String title,
    required String artist,
    String? albumId,
    String? albumName,
    String? albumArtist,
    required String albumArt,
    required String downloadUrl,
    int duration = 0,
    int? trackNumber,
    required int totalBytes,
  }) async {
    await _ensureInitialized();

    final serverId = _getCurrentServerId();
    final taskId = 'song_$songId';

    // Check if task already exists for this server
    final existing = _getScopedTask(taskId);
    if (existing != null) {
      print('Song already in queue: $title (${existing.status})');
      return;
    }

    // Create download task with download URL
    final task = DownloadTask(
      id: taskId,
      songId: songId,
      serverId: serverId,
      title: title,
      artist: artist,
      albumId: albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      albumArt: albumArt,
      downloadUrl: downloadUrl,
      duration: duration,
      trackNumber: trackNumber,
      status: DownloadStatus.pending,
      totalBytes: totalBytes,
    );

    _queue.enqueue(task);
    _fillDownloadSlots();
  }

  /// Download entire album
  Future<void> downloadAlbum({
    required List<Map<String, dynamic>> songs,
    String? albumId,
    String? albumName,
    String? albumArtist,
  }) async {
    await _ensureInitialized();

    final serverId = _getCurrentServerId();
    final newTasks = <DownloadTask>[];

    for (final song in songs) {
      final taskId = 'song_${song['id']}';

      // Skip if already exists for this server
      if (_getScopedTask(taskId) != null) continue;

      final task = DownloadTask(
        id: taskId,
        songId: song['id'] as String,
        serverId: serverId,
        title: song['title'] as String,
        artist: song['artist'] as String,
        albumId: albumId ?? song['albumId'] as String?,
        albumName: albumName ?? song['albumName'] as String?,
        albumArtist: albumArtist ?? song['albumArtist'] as String?,
        albumArt: song['albumArt'] as String,
        downloadUrl: song['downloadUrl'] as String,
        duration: song['duration'] as int? ?? 0,
        trackNumber: song['trackNumber'] as int?,
        status: DownloadStatus.pending,
        totalBytes: song['fileSize'] as int,
      );

      newTasks.add(task);
    }

    if (newTasks.isNotEmpty) {
      _queue.enqueueBatch(newTasks);
      _fillDownloadSlots();
    }
  }

  /// Pause a download
  void pauseDownload(String taskId) {
    final task = _getScopedTask(taskId);
    if (task == null) return;

    // Cancel the HTTP request
    _activeDownloads[taskId]?.cancel();
    _activeDownloads.remove(taskId);
    _activeProgress.remove(taskId); // Cleanup progress tracking

    task.status = DownloadStatus.paused;
    _queue.updateTask(task);
  }

  /// Resume a paused download
  Future<void> resumeDownload(String taskId) async {
    await _ensureInitialized();

    final task = _getScopedTask(taskId);
    if (task == null || task.status != DownloadStatus.paused) return;

    task.status = DownloadStatus.pending;
    _queue.updateTask(task);

    _fillDownloadSlots();
  }

  /// Retry a failed download
  Future<void> retryDownload(String taskId) async {
    await _ensureInitialized();

    final task = _getScopedTask(taskId);
    if (task == null || task.status != DownloadStatus.failed) return;

    task.status = DownloadStatus.pending;
    task.retryCount = 0;
    task.errorMessage = null;
    _queue.updateTask(task);

    _fillDownloadSlots();
  }

  /// Cancel a download
  void cancelDownload(String taskId) {
    final serverId = _getCurrentServerId();

    // Cancel HTTP request
    _activeDownloads[taskId]?.cancel();
    _activeDownloads.remove(taskId);
    _activeProgress.remove(taskId); // Cleanup progress tracking

    // Remove from queue (scoped to current server when available)
    _queue.dequeueWhere((task) => task.id == taskId && (serverId == null || task.serverId == serverId));

    print('Download cancelled: $taskId');
  }

  // ============================================================================
  // INTERNAL DOWNLOAD LOGIC
  // ============================================================================

  DownloadTask? _getNextPendingScoped() {
    final serverId = _getCurrentServerId();
    for (final task in _queue.queue) {
      if (task.status != DownloadStatus.pending) continue;
      if (serverId == null || task.serverId == serverId) {
        return task;
      }
    }
    return null;
  }

  /// Fill available download slots with pending tasks
  void _fillDownloadSlots() {
    while (_activeDownloadCount < _maxConcurrentDownloads) {
      final nextTask = _getNextPendingScoped();
      if (nextTask == null) {
        if (_activeDownloadCount == 0) {
          print('No more pending downloads');
        }
        return;
      }

      // Mark as downloading BEFORE incrementing to prevent double-pickup
      nextTask.status = DownloadStatus.downloading;
      _queue.updateTask(nextTask);

      _activeDownloadCount++;
      _downloadTask(nextTask);
    }
  }

  /// Download a specific task
  Future<void> _downloadTask(DownloadTask task) async {
    try {
      // Note: task.status is already set to downloading by _fillDownloadSlots()

      // Create cancel token for this download
      final cancelToken = CancelToken();
      _activeDownloads[task.id] = cancelToken;

      final filePath = _getSongFilePath(task.songId);

      // Ensure the songs directory exists
      final songDir = File(filePath).parent;
      await songDir.create(recursive: true);

      // Download the file using the actual download URL
      await _dio.download(
        task.downloadUrl,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // Update task progress fields (for later use when status changes)
          task.bytesDownloaded = received;
          if (total > 0) {
            task.totalBytes = total;
          }
          task.progress = total > 0 ? received / total : 0.0;

          // Store progress locally - do NOT update queue (avoids excessive rebuilds)
          _activeProgress[task.id] = task.progress;

          // Emit progress event for UI (lightweight, doesn't trigger queue rebuild)
          _progressController.add(DownloadProgress(
            taskId: task.id,
            progress: task.progress,
            bytesDownloaded: received,
            totalBytes: total,
          ));
        },
      );

      // Get actual file size from the downloaded file
      final downloadedFile = File(filePath);
      final fileSize = await downloadedFile.length();

      print('Download completed: ${task.title} (${_formatFileSize(fileSize)})');

      // Cache artwork for offline use (full size for detail views)
      await _cacheArtworkForDownload(task);

      // Mark as completed with actual file size
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.bytesDownloaded = fileSize;
      _queue.updateTask(task); // Update queue on status change

      _progressController.add(DownloadProgress(
        taskId: task.id,
        progress: 1.0,
        bytesDownloaded: fileSize,
        totalBytes: fileSize,
      ));

      _activeDownloads.remove(task.id);
      _activeProgress.remove(task.id); // Cleanup progress tracking

      // Decrement active count and fill available slots
      _activeDownloadCount--;
      await Future.delayed(const Duration(milliseconds: 50));
      _fillDownloadSlots();
    } on DioException catch (e) {
      _activeDownloadCount--;
      _handleDownloadError(task, e);
    } catch (e) {
      _activeDownloadCount--;
      _handleDownloadError(task, Exception('Unknown error: $e'));
    }
  }

  /// Handle download error with retry logic
  Future<void> _handleDownloadError(DownloadTask task, dynamic error) async {
    print('Download error: ${task.id} - $error');

    _activeDownloads.remove(task.id);
    _activeProgress.remove(task.id); // Cleanup progress tracking

    if (task.canRetry()) {
      task.retryCount++;
      task.status = DownloadStatus.pending;
      _queue.updateTask(task);
      print('Retrying download: ${task.title} (attempt ${task.retryCount}/${DownloadTask.maxRetries})');

      // Wait before retry, then try to fill slots (retry goes back to pending queue)
      await Future.delayed(const Duration(seconds: 5));
      _fillDownloadSlots();
    } else {
      task.status = DownloadStatus.failed;
      task.errorMessage = error.toString();
      _queue.updateTask(task);
      print('Download failed permanently: ${task.title}');

      // Continue with next download
      await Future.delayed(const Duration(milliseconds: 50));
      _fillDownloadSlots();
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Cache artwork for a downloaded song (for offline use)
  /// Caches album artwork (full + thumbnail) when albumId exists
  /// Always caches song-specific artwork for per-song covers
  Future<void> _cacheArtworkForDownload(DownloadTask task) async {
    final cacheManager = CacheManager();
    final connectionService = ConnectionService();
    if (connectionService.apiClient == null) return;

    final baseUrl = connectionService.apiClient!.baseUrl;

    try {
      if (task.albumId != null) {
        // Album song: cache both full-size and thumbnail album artwork
        await _cacheAlbumArtwork(cacheManager, baseUrl, task.albumId!);
      }
      // Always cache song-specific artwork for per-song covers
      await _cacheSongArtwork(cacheManager, baseUrl, task.songId);
    } catch (e) {
      // Don't fail the download if artwork caching fails
      print('[DownloadManager] Failed to cache artwork: $e');
    }
  }

  /// Cache album artwork (full-size and thumbnail) for offline use
  Future<void> _cacheAlbumArtwork(CacheManager cacheManager, String baseUrl, String albumId) async {
    // Cache full-size artwork (for detail views)
    final fullSizeKey = albumId;
    if (cacheManager.getArtworkPathSync(fullSizeKey) == null) {
      final fullSizeUrl = '$baseUrl/artwork/$albumId';
      await cacheManager.cacheArtwork(fullSizeKey, fullSizeUrl);
      print('[DownloadManager] Cached full-size artwork for album: $albumId');
    }

    // Cache thumbnail artwork (for list/grid views)
    final thumbnailKey = '${albumId}_thumb';
    if (cacheManager.getArtworkPathSync(thumbnailKey) == null) {
      final thumbnailUrl = '$baseUrl/artwork/$albumId?size=thumbnail';
      await cacheManager.cacheArtwork(thumbnailKey, thumbnailUrl);
      print('[DownloadManager] Cached thumbnail artwork for album: $albumId');
    }
  }

  /// Cache standalone song artwork for offline use
  Future<void> _cacheSongArtwork(CacheManager cacheManager, String baseUrl, String songId) async {
    // Standalone songs use "song_{songId}" as cache key
    final cacheKey = 'song_$songId';
    if (cacheManager.getArtworkPathSync(cacheKey) == null) {
      final artworkUrl = '$baseUrl/song-artwork/$songId';
      await cacheManager.cacheArtwork(cacheKey, artworkUrl);
      print('[DownloadManager] Cached artwork for standalone song: $songId');
    }
  }

  /// One-time backfill of artwork cache for existing downloads
  /// This ensures songs downloaded before the artwork caching feature have artwork available offline
  Future<void> _backfillArtworkForExistingDownloads() async {
    const backfillKey = 'artwork_backfill_v2';
    final prefs = await SharedPreferences.getInstance();

    // Check if backfill has already been completed
    if (prefs.getBool(backfillKey) == true) {
      return;
    }

    final connectionService = ConnectionService();
    if (connectionService.apiClient == null) {
      // Can't backfill without server connection - will try again next launch
      return;
    }

    final completedTasks = _queue.queue
        .where((task) => task.status == DownloadStatus.completed)
        .toList();

    if (completedTasks.isEmpty) {
      // No completed downloads to backfill - mark as done
      await prefs.setBool(backfillKey, true);
      return;
    }

    print('[DownloadManager] Starting artwork backfill for ${completedTasks.length} downloaded songs...');

    final cacheManager = CacheManager();
    final baseUrl = connectionService.apiClient!.baseUrl;
    int backfilledCount = 0;

    for (final task in completedTasks) {
      try {
        if (task.albumId != null) {
          await _cacheAlbumArtwork(cacheManager, baseUrl, task.albumId!);
        }
        await _cacheSongArtwork(cacheManager, baseUrl, task.songId);
        backfilledCount++;
      } catch (e) {
        // Continue with next task if one fails
        print('[DownloadManager] Backfill failed for ${task.songId}: $e');
      }
    }

    // Mark backfill as complete
    await prefs.setBool(backfillKey, true);
    print('[DownloadManager] Artwork backfill complete: $backfilledCount songs processed');
  }

  /// Get file path for a downloaded song
  String _getSongFilePath(String songId) {
    return '$_downloadPath/songs/$songId.mp3';
  }

  /// Format bytes to human readable format
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (bytes == 0 ? 0 : (math.log(bytes) / math.log(1024)).floor()).toInt();
    i = i > suffixes.length - 1 ? suffixes.length - 1 : i;
    final size = bytes / math.pow(1024, i);
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  /// Check if a song is downloaded
  Future<bool> isSongDownloaded(String songId) async {
    final task = _getScopedTask('song_$songId');
    return task?.status == DownloadStatus.completed;
  }

  /// Get downloaded song file path
  String? getDownloadedSongPath(String songId) {
    final task = _getScopedTask('song_$songId');
    if (task?.status == DownloadStatus.completed) {
      return _getSongFilePath(songId);
    }
    return null;
  }

  /// Get total downloaded size in MB
  double getTotalDownloadedSizeMB() {
    final tasks = _getScopedQueue();
    int totalBytes = 0;
    for (final task in tasks) {
      if (task.status == DownloadStatus.completed) {
        totalBytes += task.bytesDownloaded;
      }
    }
    return totalBytes / (1024 * 1024);
  }

  /// Get number of completed downloads
  int getCompletedDownloadCount() {
    final tasks = _getScopedQueue();
    return tasks.where((t) => t.status == DownloadStatus.completed).length;
  }

  /// Get queue statistics
  QueueStats getQueueStats() {
    final tasks = _getScopedQueue();
    return _buildQueueStats(tasks);
  }

  /// Get current progress for a task (from active progress tracking)
  /// Returns null if task is not actively downloading
  double? getTaskProgress(String taskId) {
    return _activeProgress[taskId];
  }

  /// Remove downloads that no longer exist in the current library
  /// Returns the number of tasks removed.
  Future<int> pruneOrphanedDownloads(Set<String> validSongIds) async {
    await _ensureInitialized();

    final tasksToRemove = _getScopedQueue()
        .where((task) => !validSongIds.contains(task.songId))
        .toList();

    if (tasksToRemove.isEmpty) {
      return 0;
    }

    for (final task in tasksToRemove) {
      // Cancel active downloads and remove from queue
      cancelDownload(task.id);
    }

    print('Pruned ${tasksToRemove.length} orphaned downloads');
    return tasksToRemove.length;
  }

  /// Clear all downloads
  Future<void> clearAllDownloads() async {
    await _ensureInitialized();

    // Cancel all active downloads
    for (final token in _activeDownloads.values) {
      token.cancel();
    }
    _activeDownloads.clear();
    _activeProgress.clear(); // Cleanup all progress tracking

    // Clear queue and database
    _queue.clear();
    await _database.clearAllDownloads();

    print('All downloads cleared');
  }

  /// Delete all downloads for a specific album
  /// Pass null albumId to delete all "Singles" (songs without an album)
  Future<void> deleteAlbumDownloads(String? albumId) async {
    await _ensureInitialized();

    // Find all tasks matching the albumId
    final tasksToDelete = _queue.queue
        .where((task) =>
            task.albumId == albumId &&
            task.status == DownloadStatus.completed)
        .toList();

    // Cancel/delete each task
    for (final task in tasksToDelete) {
      cancelDownload(task.id);
    }

    print('Deleted ${tasksToDelete.length} downloads for album: ${albumId ?? "Singles"}');
  }

  /// Get download settings
  bool getWifiOnly() => _database.getWifiOnly();

  bool getAutoDownloadFavorites() => _database.getAutoDownloadFavorites();

  int? getStorageLimit() => _database.getStorageLimit();

  /// Set download settings
  Future<void> setWifiOnly(bool wifiOnly) => _database.setWifiOnly(wifiOnly);

  Future<void> setAutoDownloadFavorites(bool auto) =>
      _database.setAutoDownloadFavorites(auto);

  Future<void> setStorageLimit(int? limitMB) =>
      _database.setStorageLimit(limitMB);

  /// Dispose resources
  void dispose() {
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
