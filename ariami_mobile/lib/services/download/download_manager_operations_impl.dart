part of 'download_manager.dart';

extension _DownloadManagerOperationsImpl on DownloadManager {
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
    for (final task in _getScopedQueue()) {
      if (!predicate(task)) continue;
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

  Future<int> _cancelInterruptedDownloadsImpl() async {
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
      if (serverId != null && task.serverId != serverId) return false;
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
