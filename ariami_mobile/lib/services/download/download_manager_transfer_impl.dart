part of 'download_manager.dart';

extension _DownloadManagerTransferImpl on DownloadManager {
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
}
