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
    if (savedQueue.isNotEmpty) {
      for (final task in savedQueue) {
        if (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.pending) {
          task.status = DownloadStatus.paused;
          task.errorMessage = appClosedDownloadPauseMessage;
        }
      }
      _queue.enqueueBatch(savedQueue);
      for (final task in savedQueue) {
        _persistedTaskSignatures[task.id] = _taskSignature(task);
      }
    }

    // Setup HTTP client
    _dio = Dio();

    // Load quality settings (for download quality/original)
    await _qualityService.initialize();

    // Get download directory
    final appDir = await getApplicationDocumentsDirectory();
    _downloadPath = '${appDir.path}/downloads';
    await Directory(_downloadPath!).create(recursive: true);

    // Listen to queue changes and persist
    _queue.queueStream.listen((tasks) {
      _scopedQueueCache = null;
      _ensureServerScope(tasks);
      _ensureUserScope(tasks);
      _scheduleQueuePersistence(tasks);

      final currentServerId = _getCurrentServerId();
      final currentUserId = _getCurrentUserId();
      final scoped = _filterTasksForCurrentScope(tasks);
      _scopedQueueCache = scoped;
      _scopedQueueCacheServerId = currentServerId;
      _scopedQueueCacheUserId = currentUserId;
      _queueController.add(scoped);
    });

    _connectionStateSubscription?.cancel();
    _connectionStateSubscription =
        ConnectionService().connectionStateStream.listen((isConnected) {
      if (isConnected) {
        _fillDownloadSlots();
        return;
      }
      _pauseScopedDownloadsForInterruption();
    });

    _initialized = true;
    print('DownloadManager initialized');

    // Run one-time artwork backfill for existing downloads (non-blocking)
    _backfillArtworkForExistingDownloads();
  }

  /// Update the maximum number of concurrent downloads (per device)
  void setMaxConcurrentDownloads(int maxConcurrent) {
    final clamped = maxConcurrent < 1 ? 1 : maxConcurrent;
    if (_maxConcurrentDownloads == clamped) return;
    _maxConcurrentDownloads = clamped;
    print('DownloadManager: Max concurrent downloads set to $clamped');
    if (_initialized) {
      _fillDownloadSlots();
    }
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

  String? _getCurrentUserId() {
    return ConnectionService().userId;
  }

  void _ensureServerScope([List<DownloadTask>? tasks]) {
    final currentServerId = _getCurrentServerId();
    if (currentServerId == null) return;

    if (_lastKnownServerId != currentServerId) {
      _lastKnownServerId = currentServerId;
    }

    final targetTasks = tasks ?? _queue.queue;
    for (final task in targetTasks) {
      task.serverId ??= currentServerId;
    }
  }

  void _ensureUserScope([List<DownloadTask>? tasks]) {
    final currentUserId = _getCurrentUserId();
    if (currentUserId == null) return;

    if (_lastKnownUserId != currentUserId) {
      _lastKnownUserId = currentUserId;
    }

    final currentServerId = _getCurrentServerId();
    if (currentServerId == null) return;

    final targetTasks = tasks ?? _queue.queue;
    for (final task in targetTasks) {
      if (task.userId == null && task.serverId == currentServerId) {
        task.userId = currentUserId;
      }
    }
  }

  List<DownloadTask> _filterTasksForCurrentScope(List<DownloadTask> tasks) {
    final currentServerId = _getCurrentServerId();
    final currentUserId = _getCurrentUserId();
    if (currentServerId == null) {
      if (currentUserId == null) {
        return List<DownloadTask>.from(tasks);
      }
      return tasks.where((task) => task.userId == currentUserId).toList();
    }
    return tasks.where((task) {
      if (task.serverId != currentServerId) return false;
      if (currentUserId == null) {
        return task.userId == null;
      }
      return task.userId == currentUserId;
    }).toList();
  }

  List<DownloadTask> _getScopedQueue() {
    final currentServerId = _getCurrentServerId();
    final currentUserId = _getCurrentUserId();
    if (_scopedQueueCache != null &&
        _scopedQueueCacheServerId == currentServerId &&
        _scopedQueueCacheUserId == currentUserId) {
      return _scopedQueueCache!;
    }

    _ensureServerScope(_queue.queue);
    _ensureUserScope(_queue.queue);
    final scoped = _filterTasksForCurrentScope(_queue.queue);
    _scopedQueueCache = scoped;
    _scopedQueueCacheServerId = currentServerId;
    _scopedQueueCacheUserId = currentUserId;
    return scoped;
  }

  void _scheduleQueuePersistence(List<DownloadTask> tasks) {
    _pendingPersistenceSnapshot = List<DownloadTask>.from(tasks);
    if (_persistenceInFlight) return;
    _persistenceInFlight = true;
    unawaited(_flushQueuePersistence());
  }

  Future<void> _flushQueuePersistence() async {
    try {
      while (true) {
        final snapshot = _pendingPersistenceSnapshot;
        if (snapshot == null) break;
        _pendingPersistenceSnapshot = null;
        try {
          await _syncQueuePersistence(snapshot);
        } catch (e) {
          // Keep processing subsequent queue snapshots even if one sync fails.
          print('[DownloadManager] Failed queue persistence sync: $e');
        }
      }
    } finally {
      _persistenceInFlight = false;
      if (_pendingPersistenceSnapshot != null) {
        _persistenceInFlight = true;
        unawaited(_flushQueuePersistence());
      }
    }
  }

  Future<void> _syncQueuePersistence(List<DownloadTask> tasks) async {
    final seenIds = <String>{};
    for (final task in tasks) {
      seenIds.add(task.id);
      final signature = _taskSignature(task);
      if (_persistedTaskSignatures[task.id] == signature) continue;
      await _database.upsertTask(task);
      _persistedTaskSignatures[task.id] = signature;
    }

    final deletedTaskIds = _persistedTaskSignatures.keys
        .where((id) => !seenIds.contains(id))
        .toList(growable: false);
    for (final taskId in deletedTaskIds) {
      await _database.deleteTask(taskId);
      _persistedTaskSignatures.remove(taskId);
    }
  }

  String _taskSignature(DownloadTask task) {
    return [
      task.songId,
      task.serverId ?? '',
      task.userId ?? '',
      task.title,
      task.artist,
      task.albumId ?? '',
      task.albumName ?? '',
      task.albumArtist ?? '',
      task.albumArt,
      task.downloadUrl,
      task.downloadQuality.name,
      task.downloadOriginal ? '1' : '0',
      task.duration.toString(),
      task.trackNumber?.toString() ?? '',
      task.status.toString(),
      task.progress.toStringAsFixed(4),
      task.bytesDownloaded.toString(),
      task.totalBytes.toString(),
      task.errorMessage ?? '',
      task.retryCount.toString(),
    ].join('|');
  }

  QueueStats _buildQueueStats(List<DownloadTask> tasks) {
    int totalTasks = tasks.length;
    int completed =
        tasks.where((t) => t.status == DownloadStatus.completed).length;
    int downloading =
        tasks.where((t) => t.status == DownloadStatus.downloading).length;
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
    _ensureUserScope();
    final currentServerId = _getCurrentServerId();
    final currentUserId = _getCurrentUserId();
    for (final task in _queue.queue) {
      if (task.id != taskId) continue;
      if (currentServerId != null && task.serverId != currentServerId) continue;
      if (currentUserId != null) {
        if (task.userId == currentUserId) return task;
        continue;
      }
      if (task.userId == null) return task;
    }
    return null;
  }

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
  }) async {
    await _ensureInitialized();

    final apiClient = ConnectionService().apiClient;
    if (apiClient == null) {
      print('DownloadManager: Cannot create download job, not connected');
      return 0;
    }

    final normalizedSongIds = _normalizeIds(songIds);
    final normalizedAlbumIds = _normalizeIds(albumIds);
    final normalizedPlaylistIds = _normalizeIds(playlistIds);

    if (normalizedSongIds.isEmpty &&
        normalizedAlbumIds.isEmpty &&
        normalizedPlaylistIds.isEmpty) {
      return 0;
    }

    final resolvedQuality =
        downloadQuality ?? _qualityService.getDownloadQuality();
    final resolvedOriginal =
        downloadOriginal ?? _qualityService.getDownloadOriginal();
    final requestedQuality =
        (resolvedOriginal ? StreamingQuality.high : resolvedQuality)
            .toApiParam();

    final createResponse = await apiClient.createV2DownloadJob(
      DownloadJobCreateRequest(
        songIds: normalizedSongIds,
        albumIds: normalizedAlbumIds,
        playlistIds: normalizedPlaylistIds,
        quality: requestedQuality,
        downloadOriginal: resolvedOriginal,
      ),
    );

    final jobQuality = StreamingQuality.fromString(createResponse.quality);
    String? cursor;
    var hasMore = true;
    var queuedCount = 0;

    while (hasMore) {
      final page = await apiClient.getV2DownloadJobItems(
        createResponse.jobId,
        cursor: cursor,
        limit: 100,
      );

      final batch = <DownloadTask>[];
      for (final item in page.items) {
        if (item.status.toLowerCase() != 'pending') continue;
        final task = _buildTaskFromDownloadJobItem(
          apiClient: apiClient,
          item: item,
          downloadQuality: jobQuality,
          downloadOriginal: createResponse.downloadOriginal,
        );
        if (task != null) {
          batch.add(task);
        }
      }

      if (batch.isNotEmpty) {
        _queue.enqueueBatch(batch);
        queuedCount += batch.length;
        _fillDownloadSlots();
      }

      hasMore = page.pageInfo.hasMore;
      cursor = page.pageInfo.nextCursor;
      if (hasMore && (cursor == null || cursor.isEmpty)) {
        break;
      }
    }

    return queuedCount;
  }

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
  }) async {
    await _ensureInitialized();

    final apiClient = ConnectionService().apiClient;
    if (apiClient == null) {
      print('DownloadManager: Cannot download, not connected to server');
      return;
    }

    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();
    final resolvedQuality =
        downloadQuality ?? _qualityService.getDownloadQuality();
    final resolvedOriginal =
        downloadOriginal ?? _qualityService.getDownloadOriginal();
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
      userId: userId,
      title: title,
      artist: artist,
      albumId: albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      albumArt: albumArt,
      downloadUrl: _buildLegacyDownloadUrl(
        apiClient: apiClient,
        songId: songId,
        downloadQuality: resolvedQuality,
        downloadOriginal: resolvedOriginal,
      ),
      downloadQuality: resolvedQuality,
      downloadOriginal: resolvedOriginal,
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
    StreamingQuality? downloadQuality,
    bool? downloadOriginal,
  }) async {
    await _ensureInitialized();

    final apiClient = ConnectionService().apiClient;
    if (apiClient == null) {
      print('DownloadManager: Cannot download, not connected to server');
      return;
    }

    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();
    final resolvedQuality =
        downloadQuality ?? _qualityService.getDownloadQuality();
    final resolvedOriginal =
        downloadOriginal ?? _qualityService.getDownloadOriginal();
    final newTasks = <DownloadTask>[];

    for (final song in songs) {
      final taskId = 'song_${song['id']}';

      // Skip if already exists for this server
      if (_getScopedTask(taskId) != null) continue;

      final task = DownloadTask(
        id: taskId,
        songId: song['id'] as String,
        serverId: serverId,
        userId: userId,
        title: song['title'] as String,
        artist: song['artist'] as String,
        albumId: albumId ?? song['albumId'] as String?,
        albumName: albumName ?? song['albumName'] as String?,
        albumArtist: albumArtist ?? song['albumArtist'] as String?,
        albumArt: song['albumArt'] as String,
        downloadUrl: _buildLegacyDownloadUrl(
          apiClient: apiClient,
          songId: song['id'] as String,
          downloadQuality: resolvedQuality,
          downloadOriginal: resolvedOriginal,
        ),
        downloadQuality: resolvedQuality,
        downloadOriginal: resolvedOriginal,
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
    task.errorMessage = null;
    _queue.updateTask(task);
  }

  /// Resume a paused download
  Future<void> resumeDownload(String taskId) async {
    await _ensureInitialized();

    final task = _getScopedTask(taskId);
    if (task == null || task.status != DownloadStatus.paused) return;

    task.status = DownloadStatus.pending;
    task.errorMessage = null;
    _queue.updateTask(task);

    _fillDownloadSlots();
  }

  /// Resume all interrupted (auto-paused) downloads in the current scope.
  Future<int> resumeInterruptedDownloads() async {
    await _ensureInitialized();

    var resumedCount = 0;
    for (final task in _getScopedQueue()) {
      if (!isInterruptedDownloadTask(task)) continue;
      task.status = DownloadStatus.pending;
      task.errorMessage = null;
      _queue.updateTask(task);
      resumedCount++;
    }

    if (resumedCount > 0) {
      _fillDownloadSlots();
    }
    return resumedCount;
  }

  /// Cancel all interrupted (auto-paused) downloads in the current scope.
  Future<int> cancelInterruptedDownloads() async {
    await _ensureInitialized();

    final interruptedTaskIds = _getScopedQueue()
        .where(isInterruptedDownloadTask)
        .map((task) => task.id)
        .toList(growable: false);

    for (final taskId in interruptedTaskIds) {
      cancelDownload(taskId);
    }
    return interruptedTaskIds.length;
  }

  /// Number of interrupted (auto-paused) downloads in the current scope.
  int getInterruptedDownloadCount() {
    return _getScopedQueue().where(isInterruptedDownloadTask).length;
  }

  /// Pause active/pending downloads and flush queue state when app closes.
  Future<void> pauseDownloadsForAppClosure() async {
    if (!_initialized) return;
    _pauseScopedDownloadsForInterruption(
      reasonMessage: appClosedDownloadPauseMessage,
    );
    await _flushQueuePersistence();
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
    final userId = _getCurrentUserId();

    // Cancel HTTP request
    _activeDownloads[taskId]?.cancel();
    _activeDownloads.remove(taskId);
    _activeProgress.remove(taskId); // Cleanup progress tracking

    // Remove from queue (scoped to current server when available)
    _queue.dequeueWhere((task) {
      if (task.id != taskId) return false;
      if (serverId != null && task.serverId != serverId) return false;
      if (userId != null) return task.userId == userId;
      return task.userId == null;
    });

    print('Download cancelled: $taskId');
  }

  // ============================================================================
  // INTERNAL DOWNLOAD LOGIC
  // ============================================================================

  DownloadTask? _getNextPendingScoped() {
    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();
    for (final task in _queue.queue) {
      if (task.status != DownloadStatus.pending) continue;
      if (serverId != null && task.serverId != serverId) continue;
      if (userId != null) {
        if (task.userId == userId) return task;
        continue;
      }
      if (task.userId == null) return task;
    }
    return null;
  }

  /// Fill available download slots with pending tasks
  void _fillDownloadSlots() {
    if (!_canProcessDownloads()) {
      return;
    }

    _queue.beginBatch();
    try {
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
    } finally {
      _queue.endBatch();
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

      final downloadUrl = await _resolveDownloadUrl(task);

      // Download the file using the resolved download URL
      await _dio.download(
        downloadUrl,
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

      // Decrement active count and fill available slots
      _activeDownloadCount--;
      await Future.delayed(const Duration(milliseconds: 50));
      _fillDownloadSlots();

      // Cache artwork after completion so network/disk prefetch doesn't block
      // download throughput or queue status updates.
      unawaited(_cacheArtworkForDownload(task));
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

    if (_getScopedTask(task.id) == null) {
      await Future.delayed(const Duration(milliseconds: 50));
      _fillDownloadSlots();
      return;
    }

    if (_isCancellationExpected(task, error)) {
      await Future.delayed(const Duration(milliseconds: 50));
      _fillDownloadSlots();
      return;
    }

    if (_isNetworkInterruptionError(error)) {
      _pauseScopedDownloadsForInterruption();
      await Future.delayed(const Duration(milliseconds: 50));
      _fillDownloadSlots();
      return;
    }

    if (task.retryCount < DownloadTask.maxRetries) {
      task.retryCount++;
      task.status = DownloadStatus.pending;
      task.errorMessage = null;
      _queue.updateTask(task);
      print(
          'Retrying download: ${task.title} (attempt ${task.retryCount}/${DownloadTask.maxRetries})');

      // Wait before retry, then try to fill slots (retry goes back to pending queue)
      final delay = _calculateRetryDelay(error, task.retryCount);
      await Future.delayed(delay);
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

  void _pauseScopedDownloadsForInterruption({
    String reasonMessage = interruptedDownloadPauseMessage,
  }) {
    final taskIdsToCancel = <String>[];
    final tasksToPause = <DownloadTask>[];

    for (final task in _queue.queue) {
      if (!_isTaskInCurrentScope(task)) continue;
      if (task.status == DownloadStatus.downloading) {
        taskIdsToCancel.add(task.id);
        tasksToPause.add(task);
        continue;
      }
      if (task.status == DownloadStatus.pending) {
        tasksToPause.add(task);
      }
    }

    for (final task in tasksToPause) {
      task.status = DownloadStatus.paused;
      task.errorMessage = reasonMessage;
      _queue.updateTask(task);
    }

    for (final taskId in taskIdsToCancel) {
      _activeDownloads[taskId]?.cancel('connection-lost');
    }
  }

  Duration _calculateRetryDelay(dynamic error, int attempt) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 429 || status == 503) {
        final backoffSeconds =
            math.min(30, 2 * math.pow(2, attempt - 1).toInt());
        final jitterMs = _retryRandom.nextInt(1000);
        return Duration(seconds: backoffSeconds, milliseconds: jitterMs);
      }
      if (status == 500) {
        final jitterMs = _retryRandom.nextInt(1000);
        return Duration(seconds: 3, milliseconds: jitterMs);
      }
    }
    return const Duration(seconds: 5);
  }

  bool _canProcessDownloads() {
    final connection = ConnectionService();
    return connection.isConnected && connection.apiClient != null;
  }

  bool _isTaskInCurrentScope(DownloadTask task) {
    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();

    if (serverId != null && task.serverId != serverId) {
      return false;
    }
    if (userId != null && task.userId != userId) {
      return false;
    }
    return true;
  }

  bool _isCancellationExpected(DownloadTask task, dynamic error) {
    if (error is! DioException) {
      return false;
    }

    final cancelled =
        error.type == DioExceptionType.cancel || CancelToken.isCancel(error);
    if (!cancelled) {
      return false;
    }

    return task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.cancelled;
  }

  bool _isNetworkInterruptionError(dynamic error) {
    if (error is! DioException) {
      return false;
    }

    if (error.type == DioExceptionType.cancel || CancelToken.isCancel(error)) {
      return false;
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }

    return error.response == null;
  }

  String _buildLegacyDownloadUrl({
    required ApiClient apiClient,
    required String songId,
    required StreamingQuality downloadQuality,
    required bool downloadOriginal,
  }) {
    if (downloadOriginal) {
      return apiClient.getDownloadUrl(songId);
    }
    return apiClient.getDownloadUrlWithQuality(songId, downloadQuality);
  }

  List<String> _normalizeIds(List<String> ids) {
    final unique = <String>{};
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty) {
        unique.add(trimmed);
      }
    }
    return unique.toList();
  }

  DownloadTask? _buildTaskFromDownloadJobItem({
    required ApiClient apiClient,
    required DownloadJobItemModel item,
    required StreamingQuality downloadQuality,
    required bool downloadOriginal,
  }) {
    final taskId = 'song_${item.songId}';
    if (_getScopedTask(taskId) != null) {
      return null;
    }

    final albumArt = item.albumId != null
        ? '${apiClient.baseUrl}/artwork/${item.albumId}'
        : '';
    final title = item.title.trim().isNotEmpty ? item.title : item.songId;
    final artist =
        item.artist.trim().isNotEmpty ? item.artist : 'Unknown Artist';

    return DownloadTask(
      id: taskId,
      songId: item.songId,
      serverId: _getCurrentServerId(),
      userId: _getCurrentUserId(),
      title: title,
      artist: artist,
      albumId: item.albumId,
      albumName: item.albumName,
      albumArtist: item.albumArtist,
      albumArt: albumArt,
      downloadUrl: _buildLegacyDownloadUrl(
        apiClient: apiClient,
        songId: item.songId,
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      ),
      downloadQuality: downloadQuality,
      downloadOriginal: downloadOriginal,
      duration: item.durationSeconds,
      trackNumber: item.trackNumber,
      status: DownloadStatus.pending,
      totalBytes: item.fileSizeBytes ?? 0,
    );
  }

  Future<String> _resolveDownloadUrl(DownloadTask task) async {
    final apiClient = ConnectionService().apiClient;
    if (apiClient == null) {
      throw Exception('Not connected to server');
    }

    if (ConnectionService().isAuthenticated) {
      final tokenQuality = (!task.downloadOriginal &&
              task.downloadQuality != StreamingQuality.high)
          ? task.downloadQuality.toApiParam()
          : null;
      final ticketResponse = await apiClient.getStreamTicket(
        task.songId,
        quality: tokenQuality,
      );

      final urlQuality =
          task.downloadOriginal ? StreamingQuality.high : task.downloadQuality;
      return apiClient.getDownloadUrlWithToken(
        task.songId,
        ticketResponse.streamToken,
        quality: urlQuality,
      );
    }

    return _buildLegacyDownloadUrl(
      apiClient: apiClient,
      songId: task.songId,
      downloadQuality: task.downloadQuality,
      downloadOriginal: task.downloadOriginal,
    );
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Cache artwork for a downloaded song (for offline use) by reading embedded
  /// art from the local audio file — no extra HTTP requests to the server.
  Future<void> _cacheArtworkForDownload(DownloadTask task) async {
    final cacheManager = CacheManager();
    final localPath = _getSongFilePath(task.songId);
    final file = File(localPath);
    if (!await file.exists()) return;

    try {
      final bytes = await LocalArtworkExtractor.extractArtwork(localPath);
      if (bytes == null || bytes.isEmpty) {
        print('[DownloadManager] No embedded artwork for song ${task.songId}');
        return;
      }

      final songKey = 'song_${task.songId}';
      if (!await cacheManager.isArtworkCached(songKey)) {
        await cacheManager.cacheArtworkFromBytes(songKey, bytes);
      }

      if (task.albumId != null &&
          !await cacheManager.isArtworkCached(task.albumId!)) {
        await cacheManager.cacheArtworkFromBytes(task.albumId!, bytes);
      }
      if (task.albumId != null) {
        final thumbKey = '${task.albumId!}_thumb';
        if (!await cacheManager.isArtworkCached(thumbKey)) {
          await cacheManager.cacheArtworkFromBytes(thumbKey, bytes);
        }
      }
    } catch (e) {
      // Don't fail the download if artwork caching fails
      print('[DownloadManager] Failed to cache artwork: $e');
    }
  }

  /// One-time backfill: extract embedded art from already-downloaded files
  /// (works offline; no server required).
  Future<void> _backfillArtworkForExistingDownloads() async {
    const backfillKey = 'artwork_backfill_v4';
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(backfillKey) == true) {
      return;
    }

    final completedTasks = _queue.queue
        .where((task) => task.status == DownloadStatus.completed)
        .toList();

    if (completedTasks.isEmpty) {
      await prefs.setBool(backfillKey, true);
      return;
    }

    print(
        '[DownloadManager] Starting local artwork backfill for ${completedTasks.length} downloaded songs...');

    final cacheManager = CacheManager();
    var backfilledCount = 0;

    for (final task in completedTasks) {
      try {
        final localPath = _getSongFilePath(task.songId);
        final file = File(localPath);
        if (!await file.exists()) continue;

        final bytes = await LocalArtworkExtractor.extractArtwork(localPath);
        if (bytes == null || bytes.isEmpty) continue;

        final songKey = 'song_${task.songId}';
        if (!await cacheManager.isArtworkCached(songKey)) {
          await cacheManager.cacheArtworkFromBytes(songKey, bytes);
        }
        if (task.albumId != null &&
            !await cacheManager.isArtworkCached(task.albumId!)) {
          await cacheManager.cacheArtworkFromBytes(task.albumId!, bytes);
        }
        if (task.albumId != null) {
          final thumbKey = '${task.albumId!}_thumb';
          if (!await cacheManager.isArtworkCached(thumbKey)) {
            await cacheManager.cacheArtworkFromBytes(thumbKey, bytes);
          }
        }
        backfilledCount++;
      } catch (e) {
        print('[DownloadManager] Backfill failed for ${task.songId}: $e');
      }
    }

    await prefs.setBool(backfillKey, true);
    print(
        '[DownloadManager] Local artwork backfill complete: $backfilledCount songs processed');
  }

  /// Get file path for a downloaded song
  String _getSongFilePath(String songId) {
    return '$_downloadPath/songs/$songId.mp3';
  }

  /// Format bytes to human readable format
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i =
        (bytes == 0 ? 0 : (math.log(bytes) / math.log(1024)).floor()).toInt();
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

  /// Get any downloaded local file path for a given album.
  /// Returns null when the album has no completed downloads.
  String? getAnyDownloadedSongPathForAlbum(String albumId) {
    final normalizedAlbumId = albumId.trim();
    if (normalizedAlbumId.isEmpty) return null;

    for (final task in _getScopedQueue()) {
      if (task.status == DownloadStatus.completed &&
          task.albumId == normalizedAlbumId) {
        return _getSongFilePath(task.songId);
      }
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
            task.albumId == albumId && task.status == DownloadStatus.completed)
        .toList();

    // Cancel/delete each task
    for (final task in tasksToDelete) {
      cancelDownload(task.id);
    }

    print(
        'Deleted ${tasksToDelete.length} downloads for album: ${albumId ?? "Singles"}');
  }

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
