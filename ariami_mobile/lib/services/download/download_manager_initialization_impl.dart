part of 'download_manager.dart';

extension _DownloadManagerInitializationImpl on DownloadManager {
  Future<void> _initializeImpl() async {
    if (_initialized) return;

    // Setup database
    _database = await DownloadDatabase.create();

    // Get download directory before queue recovery so partial-file lookups use
    // the real application path.
    final appDir = await getApplicationDocumentsDirectory();
    _downloadPath = '${appDir.path}/downloads';
    await Directory(_downloadPath!).create(recursive: true);

    // Load queue from storage into the already-initialized _queue
    final savedQueue = await _database.loadDownloadQueue();
    if (savedQueue.isNotEmpty) {
      for (final task in savedQueue) {
        final partialBytes = await _getPartialSongFileSize(task.songId);
        if (partialBytes != null && partialBytes > 0) {
          task.bytesDownloaded = partialBytes;
          if (task.totalBytes > 0) {
            task.progress = partialBytes / task.totalBytes;
          }
        }
        if (task.nativeTaskId != null &&
            task.status == DownloadStatus.downloading) {
          unawaited(_reconcileNativeDownloadOnLaunch(task));
          continue;
        }
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

    // Remove stale local files that no longer have queue metadata.
    unawaited(_cleanupStaleDownloadFiles());

    // Run one-time artwork backfill for existing downloads (non-blocking)
    unawaited(_backfillArtworkForExistingDownloads());
  }

  void _setMaxConcurrentDownloadsImpl(int maxConcurrent) {
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
      task.nativeBackend ?? '',
      task.nativeTaskId ?? '',
    ].join('|');
  }

  Future<void> _reconcileNativeDownloadOnLaunch(DownloadTask task) async {
    final nativeTaskId = task.nativeTaskId;
    if (nativeTaskId == null) return;

    final snapshot = await _nativeDownloadService.queryDownload(
      taskId: task.id,
      nativeTaskId: nativeTaskId,
    );

    if (snapshot.state == NativeDownloadState.completed) {
      final filePath = _getSongFilePath(task.songId);
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.bytesDownloaded = fileSize;
        task.totalBytes = fileSize;
        task.errorMessage = null;
        task.nativeBackend = null;
        task.nativeTaskId = null;
        _queue.updateTask(task);
      }
      return;
    }

    if (snapshot.state == NativeDownloadState.enqueued ||
        snapshot.state == NativeDownloadState.running ||
        snapshot.state == NativeDownloadState.paused) {
      task.status = DownloadStatus.downloading;
      task.bytesDownloaded = snapshot.bytesDownloaded;
      if (snapshot.totalBytes > 0) {
        task.totalBytes = snapshot.totalBytes;
        task.progress = snapshot.bytesDownloaded / snapshot.totalBytes;
      }
      _queue.updateTask(task);
      _activeDownloadCount++;
      unawaited(_pollNativeDownload(task, _getSongFilePath(task.songId)));
      return;
    }

    task.status = DownloadStatus.paused;
    task.errorMessage = appClosedDownloadPauseMessage;
    task.nativeBackend = null;
    task.nativeTaskId = null;
    _queue.updateTask(task);
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
}
