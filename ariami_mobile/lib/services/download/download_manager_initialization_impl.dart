part of 'download_manager.dart';

extension _DownloadManagerInitializationImpl on DownloadManager {
  Future<void> _initializeImpl() async {
    if (_initialized) return;

    // Setup database
    _database = await DownloadDatabase.create();
    _coolerDownloadsEnabled = _database.getCoolerDownloads();

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
      _invalidateScopedQueueCache();
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
        // Connection-loss pauses are mechanical, not user intent: resume
        // them on reconnect so a network blip (screen-off Wi-Fi power-save,
        // Tailscale route change) doesn't strand a batch mid-download. Only
        // this pause reason auto-resumes — user pauses and app-closure
        // pauses keep their existing recovery flows.
        _resumeInterruptedDownloadsWhere((task) =>
            task.status == DownloadStatus.paused &&
            task.errorMessage == interruptedDownloadPauseMessage);
        _fillDownloadSlots();
        return;
      }
      _pauseScopedDownloadsForInterruption();
    });

    _initialized = true;
    print('DownloadManager initialized');

    // The saved queue was enqueued before the internal queue listener was
    // attached, so that load never reached [queueStream] (broadcast streams
    // drop events with no listeners) and never invalidated the scoped-queue
    // cache. A screen opened during initialization has therefore read — and
    // cached — an empty queue, and on an offline cold launch no later
    // connect/disconnect event arrives to correct it, leaving downloads
    // looking absent until the queue next changes. Broadcast the restored
    // scoped queue now so early-built consumers converge on the real state.
    _refreshScopedQueueBroadcastImpl();

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

  void _setAppInForegroundImpl(bool isForeground) {
    if (_isAppInForeground == isForeground) return;
    _isAppInForeground = isForeground;
    print('DownloadManager: App foreground state set to $isForeground');
    if (isForeground && _initialized) {
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

  /// All API base URLs that identify the currently-connected server across
  /// every known network route (active, LAN, Tailscale).
  ///
  /// Downloads are scoped by [DownloadTask.serverId], which stores the active
  /// API base URL at download time. The same server is reachable at different
  /// addresses depending on the route (LAN IP vs Tailscale IP), so matching a
  /// single base URL made downloads "disappear" when the route changed — for
  /// example after going back online over Tailscale, where the checkmark was
  /// lost because the LAN-scoped task no longer matched the Tailscale base URL.
  /// Matching against every known endpoint keeps a server's downloads in scope
  /// regardless of which route is currently active.
  Set<String> _currentServerScopeIds() {
    final info =
        ConnectionService().apiClient?.serverInfo ?? ConnectionService().serverInfo;
    final ids = <String>{};
    if (info != null) {
      void addAddress(String? address) {
        if (address == null || address.isEmpty) return;
        ids.add('http://$address:${info.port}/api');
      }

      addAddress(info.server);
      addAddress(info.lanServer);
      addAddress(info.tailscaleServer);
    }
    final current = _getCurrentServerId();
    if (current != null) ids.add(current);
    return ids;
  }

  /// Whether [taskServerId] refers to the currently-connected server, tolerant
  /// of which network route (LAN/Tailscale) is active. See
  /// [_currentServerScopeIds].
  bool _serverIdInCurrentScope(String? taskServerId) {
    if (taskServerId == null) return false;
    return _currentServerScopeIds().contains(taskServerId);
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
    // Computed once per filter pass: rebuilding this set per task made every
    // queue event O(N^2), which stalled the UI isolate on large queues.
    final scopeIds = _currentServerScopeIds();
    return tasks.where((task) {
      if (task.serverId == null || !scopeIds.contains(task.serverId)) {
        return false;
      }
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

  void _invalidateScopedQueueCache() {
    _scopedQueueCache = null;
    _scopedQueueCacheServerId = null;
    _scopedQueueCacheUserId = null;
  }

  void _refreshScopedQueueBroadcastImpl() {
    if (!_initialized) return;
    _invalidateScopedQueueCache();
    _queueController.add(_getScopedQueue());
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
    final upserts = <DownloadTask>[];
    final upsertSignatures = <String, String>{};
    for (final task in tasks) {
      seenIds.add(task.id);
      final signature = _taskSignature(task);
      if (_persistedTaskSignatures[task.id] == signature) continue;
      upserts.add(task);
      upsertSignatures[task.id] = signature;
    }

    final deletedTaskIds = _persistedTaskSignatures.keys
        .where((id) => !seenIds.contains(id))
        .toList(growable: false);

    if (upserts.isEmpty && deletedTaskIds.isEmpty) return;

    // One platform-channel round trip for the whole diff; row-by-row awaits
    // made mass status changes (pause/resume/cancel all) crawl and left a
    // half-written queue if the OS killed the app mid-flush.
    await _database.applyTaskChanges(
      upserts: upserts,
      deletedIds: deletedTaskIds,
    );
    _persistedTaskSignatures.addAll(upsertSignatures);
    for (final taskId in deletedTaskIds) {
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
      if (currentServerId != null && !_serverIdInCurrentScope(task.serverId)) {
        continue;
      }
      if (currentUserId != null) {
        if (task.userId == currentUserId) return task;
        continue;
      }
      if (task.userId == null) return task;
    }
    return null;
  }
}
