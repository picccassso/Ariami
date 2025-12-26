import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../database/download_database.dart';
import '../../models/download_task.dart';
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
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  final StreamController<List<DownloadTask>> _queueController =
      StreamController<List<DownloadTask>>.broadcast();

  bool _initialized = false;
  String? _downloadPath;

  /// Stream of download progress updates
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Stream of queue updates
  Stream<List<DownloadTask>> get queueStream => _queueController.stream;

  /// Get current queue
  List<DownloadTask> get queue => _queue.queue;

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
      _queueController.add(tasks);
    });

    _initialized = true;
    print('DownloadManager initialized');
  }

  /// Ensure initialization
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
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

    final taskId = 'song_$songId';

    // Check if already downloading/completed
    final existing = _queue.getTask(taskId);
    if (existing != null &&
        (existing.status == DownloadStatus.downloading ||
            existing.status == DownloadStatus.completed)) {
      print('Song already downloading or downloaded: $title');
      return;
    }

    // Create download task with download URL
    final task = DownloadTask(
      id: taskId,
      songId: songId,
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
    _startNextDownload();
  }

  /// Download entire album
  Future<void> downloadAlbum({
    required List<Map<String, dynamic>> songs,
    String? albumId,
    String? albumName,
    String? albumArtist,
  }) async {
    await _ensureInitialized();

    final newTasks = <DownloadTask>[];

    for (final song in songs) {
      final taskId = 'song_${song['id']}';

      // Skip if already exists
      if (_queue.getTask(taskId) != null) continue;

      final task = DownloadTask(
        id: taskId,
        songId: song['id'] as String,
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
      _startNextDownload();
    }
  }

  /// Pause a download
  void pauseDownload(String taskId) {
    final task = _queue.getTask(taskId);
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

    final task = _queue.getTask(taskId);
    if (task == null || task.status != DownloadStatus.paused) return;

    task.status = DownloadStatus.pending;
    _queue.updateTask(task);

    _startNextDownload();
  }

  /// Retry a failed download
  Future<void> retryDownload(String taskId) async {
    await _ensureInitialized();

    final task = _queue.getTask(taskId);
    if (task == null || task.status != DownloadStatus.failed) return;

    task.status = DownloadStatus.pending;
    task.retryCount = 0;
    task.errorMessage = null;
    _queue.updateTask(task);

    _startNextDownload();
  }

  /// Cancel a download
  void cancelDownload(String taskId) {
    // Cancel HTTP request
    _activeDownloads[taskId]?.cancel();
    _activeDownloads.remove(taskId);
    _activeProgress.remove(taskId); // Cleanup progress tracking

    // Remove from queue
    _queue.dequeue(taskId);

    print('Download cancelled: $taskId');
  }

  // ============================================================================
  // INTERNAL DOWNLOAD LOGIC
  // ============================================================================

  /// Start downloading the next pending task
  void _startNextDownload() {
    final nextTask = _queue.getNextPending();
    if (nextTask == null) {
      print('No more pending downloads');
      return;
    }

    _downloadTask(nextTask);
  }

  /// Download a specific task
  Future<void> _downloadTask(DownloadTask task) async {
    try {
      // Mark as downloading
      task.status = DownloadStatus.downloading;
      _queue.updateTask(task);

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

      // Continue with next download
      _startNextDownload();
    } on DioException catch (e) {
      _handleDownloadError(task, e);
    } catch (e) {
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

      // Wait before retry
      await Future.delayed(const Duration(seconds: 5));
      _downloadTask(task);
    } else {
      task.status = DownloadStatus.failed;
      task.errorMessage = error.toString();
      _queue.updateTask(task);
      print('Download failed permanently: ${task.title}');

      // Continue with next download
      _startNextDownload();
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

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
    final task = _queue.getTask('song_$songId');
    return task?.status == DownloadStatus.completed;
  }

  /// Get downloaded song file path
  String? getDownloadedSongPath(String songId) {
    final task = _queue.getTask('song_$songId');
    if (task?.status == DownloadStatus.completed) {
      return _getSongFilePath(songId);
    }
    return null;
  }

  /// Get total downloaded size in MB
  double getTotalDownloadedSizeMB() {
    return _database.getTotalDownloadSizeMB();
  }

  /// Get number of completed downloads
  int getCompletedDownloadCount() {
    return _database.getCompletedDownloadCount();
  }

  /// Get queue statistics
  QueueStats getQueueStats() {
    return _queue.getStats();
  }

  /// Get current progress for a task (from active progress tracking)
  /// Returns null if task is not actively downloading
  double? getTaskProgress(String taskId) {
    return _activeProgress[taskId];
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
