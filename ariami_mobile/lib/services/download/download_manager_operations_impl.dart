part of 'download_manager.dart';

extension _DownloadManagerOperationsImpl on DownloadManager {
  /// Re-queue existing paused/failed tasks named by a download action.
  ///
  /// Download entry points used to silently skip any song that already had a
  /// queue task — so after an interruption left the whole library paused,
  /// "Download all" became a no-op. Explicitly asking for a song again is an
  /// instruction to get it downloaded, so stalled tasks go back to pending.
  /// Returns the number of tasks re-queued.
  Future<int> _requeueExistingTasksForDownload(
    List<DownloadTask> existingTasks,
  ) async {
    final discardPartialSongIds = <String>[];
    var requeuedCount = 0;

    _queue.beginBatch();
    try {
      for (final task in existingTasks) {
        if (task.status != DownloadStatus.paused &&
            task.status != DownloadStatus.failed) {
          continue;
        }
        final message = task.errorMessage ?? '';
        if (task.status == DownloadStatus.failed &&
            (message.contains('mismatch') ||
                message.contains('Range not satisfiable'))) {
          discardPartialSongIds.add(task.songId);
          task.bytesDownloaded = 0;
          task.progress = 0;
        }
        task.status = DownloadStatus.pending;
        task.errorMessage = null;
        task.retryCount = 0;
        _queue.updateTask(task);
        sessionTaskIds.add(task.id);
        requeuedCount++;
      }
    } finally {
      _queue.endBatch();
    }

    // Corrupt partials are discarded before slots fill so a restarting
    // download can't append to a file that is about to be deleted.
    for (final songId in discardPartialSongIds) {
      await _deletePartialSongFileIfUnreferenced(songId, force: true);
    }
    return requeuedCount;
  }

  Future<int> _enqueueDownloadJobImpl({
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
      final existingTasks = <DownloadTask>[];
      for (final item in page.items) {
        if (item.status.toLowerCase() != 'pending') continue;
        final existing = _getScopedTask('song_${item.songId}');
        if (existing != null) {
          existingTasks.add(existing);
          continue;
        }
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

      final requeuedCount =
          await _requeueExistingTasksForDownload(existingTasks);
      if (batch.isNotEmpty) {
        _trackSessionTasks(batch);
        _queue.enqueueBatch(batch);
      }
      queuedCount += batch.length + requeuedCount;
      if (batch.isNotEmpty || requeuedCount > 0) {
        _fillDownloadSlots();
      }

      hasMore = page.pageInfo.hasMore;
      cursor = page.pageInfo.nextCursor;
      if (hasMore && (cursor == null || cursor.isEmpty)) {
        break;
      }
    }

    // Kick the queue even when every item already existed in an active
    // state, in case pending tasks are sitting without a slot filler.
    _fillDownloadSlots();

    // The server job exists only to orchestrate this enqueue. Cancel it so
    // it stops counting against the per-user job/item quotas — abandoned
    // ready jobs otherwise pile up until job creation starts returning 429.
    try {
      await apiClient.cancelV2DownloadJob(createResponse.jobId);
    } catch (e) {
      // Best-effort: the server also expires stale ready jobs on its own.
      print('[DownloadManager] Failed to cancel download job: $e');
    }

    return queuedCount;
  }

  Future<void> _downloadSongImpl({
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

    // Individual-song entry points often only have the normalized album ID.
    // Resolve the title/artist before creating the durable task so the
    // Downloads screen does not have to guess later.
    final resolvedAlbum = await AlbumMetadataResolver().resolve(albumId);
    if (albumName?.trim().isEmpty ?? true) albumName = resolvedAlbum?.title;
    if (albumArtist?.trim().isEmpty ?? true) {
      albumArtist = resolvedAlbum?.artist;
    }

    // A stalled (paused/failed) task for this song is re-queued; an actively
    // downloading, pending, or completed one is left alone.
    var existing = _getScopedTask(taskId);
    if (existing != null) {
      if (resolvedAlbum != null &&
          ((existing.albumName?.trim().isEmpty ?? true) ||
              (existing.albumArtist?.trim().isEmpty ?? true))) {
        final replacement = _buildDownloadTaskWithAlbumMetadata(
          existing,
          resolvedAlbum,
        );
        if (_queue.replaceTask(existing.id, replacement)) {
          existing = replacement;
        }
      }
      final requeued = await _requeueExistingTasksForDownload([existing]);
      if (requeued > 0) {
        _fillDownloadSlots();
      } else {
        print('Song already in queue: $title (${existing.status})');
      }
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

    _trackSessionTasks([task]);
    _queue.enqueue(task);
    _fillDownloadSlots();
  }

  Future<void> _downloadAlbumImpl({
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
    final existingTasks = <DownloadTask>[];

    for (final song in songs) {
      final taskId = 'song_${song['id']}';

      // Existing tasks are re-queued if stalled rather than skipped.
      final existing = _getScopedTask(taskId);
      if (existing != null) {
        existingTasks.add(existing);
        continue;
      }

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

    final requeuedCount = await _requeueExistingTasksForDownload(existingTasks);
    if (newTasks.isNotEmpty) {
      _trackSessionTasks(newTasks);
      _queue.enqueueBatch(newTasks);
    }
    if (newTasks.isNotEmpty || requeuedCount > 0) {
      _fillDownloadSlots();
    }
  }

  void _pauseDownloadImpl(String taskId) {
    final task = _getScopedTask(taskId);
    if (task == null) return;

    // Cancel the HTTP request
    _activeDownloads[taskId]?.cancel();
    _activeDownloads.remove(taskId);
    _activeProgress.remove(taskId); // Cleanup progress tracking
    final nativeTaskId = task.nativeTaskId;
    if (nativeTaskId != null) {
      unawaited(_nativeDownloadService.cancelDownload(
        taskId: task.id,
        nativeTaskId: nativeTaskId,
      ));
      task.nativeBackend = null;
      task.nativeTaskId = null;
    }

    task.status = DownloadStatus.paused;
    task.errorMessage = null;
    _queue.updateTask(task);
  }

  Future<void> _resumeDownloadImpl(String taskId) async {
    await _ensureInitialized();

    final task = _getScopedTask(taskId);
    if (task == null || task.status != DownloadStatus.paused) return;

    task.status = DownloadStatus.pending;
    task.errorMessage = null;
    _queue.updateTask(task);

    _fillDownloadSlots();
  }

  Future<int> _resumeInterruptedDownloadsImpl() async {
    await _ensureInitialized();

    return _resumeInterruptedDownloadsWhere(isInterruptedDownloadTask);
  }

  Future<int> _resumeLifecycleInterruptedDownloadsImpl() async {
    await _ensureInitialized();

    return _resumeInterruptedDownloadsWhere((task) =>
        task.status == DownloadStatus.paused &&
        task.errorMessage == lifecycleDownloadPauseMessage);
  }

  int _resumeInterruptedDownloadsWhere(bool Function(DownloadTask) predicate) {
    var resumedCount = 0;
    _queue.beginBatch();
    try {
      for (final task in _getScopedQueue()) {
        if (!predicate(task)) continue;
        task.status = DownloadStatus.pending;
        task.errorMessage = null;
        _queue.updateTask(task);
        resumedCount++;
      }
    } finally {
      _queue.endBatch();
    }

    if (resumedCount > 0) {
      _fillDownloadSlots();
    }
    return resumedCount;
  }

  Future<int> _cancelInterruptedDownloadsImpl() async {
    await _ensureInitialized();

    final interruptedTaskIds = _getScopedQueue()
        .where(isInterruptedDownloadTask)
        .map((task) => task.id)
        .toList(growable: false);

    _queue.beginBatch();
    try {
      for (final taskId in interruptedTaskIds) {
        cancelDownload(taskId);
      }
    } finally {
      _queue.endBatch();
    }
    return interruptedTaskIds.length;
  }

  int _getInterruptedDownloadCountImpl() {
    return _getScopedQueue().where(isInterruptedDownloadTask).length;
  }

  Future<void> _pauseDownloadsForAppClosureImpl() async {
    if (!_initialized) return;
    _pauseScopedDownloadsForInterruption(
      reasonMessage: appClosedDownloadPauseMessage,
    );
    await _flushQueuePersistence();
  }

  Future<void> _pauseDownloadsForLifecycleInterruptionImpl() async {
    if (!_initialized) return;
    _pauseScopedDownloadsForInterruption(
      reasonMessage: lifecycleDownloadPauseMessage,
    );
    await _flushQueuePersistence();
  }

  Future<void> _retryDownloadImpl(String taskId) async {
    await _ensureInitialized();

    final task = _getScopedTask(taskId);
    if (task == null || task.status != DownloadStatus.failed) return;

    final shouldDiscardPartial =
        (task.errorMessage ?? '').contains('mismatch') ||
            (task.errorMessage ?? '').contains('Range not satisfiable');
    if (shouldDiscardPartial) {
      await _deletePartialSongFileIfUnreferenced(task.songId, force: true);
      task.bytesDownloaded = 0;
      task.progress = 0;
    } else {
      final partialBytes = await _getPartialSongFileSize(task.songId);
      if (partialBytes != null && partialBytes > 0) {
        task.bytesDownloaded = partialBytes;
        if (task.totalBytes > 0) {
          task.progress = partialBytes / task.totalBytes;
        }
      }
    }

    task.status = DownloadStatus.pending;
    task.retryCount = 0;
    task.errorMessage = null;
    _queue.updateTask(task);

    _fillDownloadSlots();
  }

  void _cancelDownloadImpl(String taskId) {
    final targetTask = _getScopedTask(taskId);
    if (targetTask == null) return;

    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();

    // Cancel HTTP request
    _activeDownloads[taskId]?.cancel();
    _activeDownloads.remove(taskId);
    _activeProgress.remove(taskId); // Cleanup progress tracking
    final nativeTaskId = targetTask.nativeTaskId;
    if (nativeTaskId != null) {
      unawaited(_nativeDownloadService.cancelDownload(
        taskId: targetTask.id,
        nativeTaskId: nativeTaskId,
      ));
    }

    // Remove from queue (scoped to current server when available)
    _queue.dequeueWhere((task) {
      if (task.id != taskId) return false;
      if (serverId != null && !_serverIdInCurrentScope(task.serverId)) {
        return false;
      }
      if (userId != null) return task.userId == userId;
      return task.userId == null;
    });
    unawaited(_deleteSongFileIfUnreferenced(targetTask.songId));
    unawaited(_deletePartialSongFileIfUnreferenced(targetTask.songId));

    print('Download cancelled: $taskId');
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

  void _trackSessionTasks(Iterable<DownloadTask> tasks) {
    for (final task in tasks) {
      sessionTaskIds.add(task.id);
    }
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
    final title = _resolveDownloadTitle(item);
    final artist = _resolveDownloadArtist(item);

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

  String _resolveDownloadTitle(DownloadJobItemModel item) {
    final title = item.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    final albumName = item.albumName?.trim();
    if (albumName != null && albumName.isNotEmpty) {
      if (item.trackNumber != null && item.trackNumber! > 0) {
        return '$albumName · track ${item.trackNumber}';
      }
      return 'Track from $albumName';
    }
    return item.songId;
  }

  String _resolveDownloadArtist(DownloadJobItemModel item) {
    final artist = item.artist.trim();
    if (artist.isNotEmpty) {
      return artist;
    }
    final albumArtist = item.albumArtist?.trim();
    if (albumArtist != null && albumArtist.isNotEmpty) {
      return albumArtist;
    }
    return 'Unknown Artist';
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
      final ticketResponse = await apiClient.getDownloadTicket(
        task.songId,
        quality: tokenQuality,
      );

      final urlQuality =
          task.downloadOriginal ? StreamingQuality.high : task.downloadQuality;
      return apiClient.getDownloadUrlWithDownloadToken(
        task.songId,
        ticketResponse.downloadToken,
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
}
