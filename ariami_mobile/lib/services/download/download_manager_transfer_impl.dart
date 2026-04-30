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
      final partialPath = _getPartialSongFilePath(task.songId);

      // Ensure the songs directory exists
      final songDir = File(filePath).parent;
      await songDir.create(recursive: true);

      final downloadUrl = await _resolveDownloadUrl(task);
      if (await _downloadTaskWithNativeService(
        task: task,
        downloadUrl: downloadUrl,
        filePath: filePath,
      )) {
        return;
      }

      final partialFile = File(partialPath);
      final finalFile = File(filePath);
      var resumeOffset =
          await partialFile.exists() ? await partialFile.length() : 0;
      final requestedRange = resumeOffset > 0;

      final headers = <String, String>{};
      if (requestedRange) {
        headers[HttpHeaders.rangeHeader] = 'bytes=$resumeOffset-';
      }

      final response = await _dio.get<ResponseBody>(
        downloadUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
        ),
      );

      if (response.statusCode == 416) {
        await _deletePartialSongFileIfUnreferenced(task.songId, force: true);
        throw Exception('Range not satisfiable');
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: Response<dynamic>(
            requestOptions: response.requestOptions,
            statusCode: response.statusCode,
            headers: response.headers,
          ),
          type: DioExceptionType.badResponse,
          message: 'Unexpected download status: ${response.statusCode}',
        );
      }

      // Server ignored range resume; reset stale partial and write full body.
      if (requestedRange && response.statusCode == 200 && resumeOffset > 0) {
        await partialFile.delete();
        resumeOffset = 0;
      }

      final writeMode = resumeOffset > 0 ? FileMode.append : FileMode.write;
      final sink = partialFile.openWrite(mode: writeMode);
      final contentRange =
          response.headers.value(HttpHeaders.contentRangeHeader);
      final contentLengthHeader =
          response.headers.value(HttpHeaders.contentLengthHeader);
      final responseLength = int.tryParse(contentLengthHeader ?? '');
      final expectedTotalFromRange =
          _parseTotalBytesFromContentRange(contentRange);

      final expectedTotalBytes = expectedTotalFromRange ??
          (responseLength != null ? responseLength + resumeOffset : null);

      var receivedThisResponse = 0;
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          receivedThisResponse += chunk.length;

          final downloaded = resumeOffset + receivedThisResponse;
          task.bytesDownloaded = downloaded;
          if (expectedTotalBytes != null && expectedTotalBytes > 0) {
            task.totalBytes = expectedTotalBytes;
            task.progress = downloaded / expectedTotalBytes;
          } else {
            task.progress = 0.0;
          }

          _activeProgress[task.id] = task.progress;
          _progressController.add(DownloadProgress(
            taskId: task.id,
            progress: task.progress,
            bytesDownloaded: downloaded,
            totalBytes: task.totalBytes,
          ));
        }
      } finally {
        await sink.close();
      }

      final fileSize = await partialFile.length();
      final expectedFinalBytes = expectedTotalBytes ??
          (task.totalBytes > 0 ? task.totalBytes : fileSize);
      if (expectedFinalBytes > 0 && fileSize != expectedFinalBytes) {
        throw Exception(
          'Downloaded file size mismatch: expected $expectedFinalBytes got $fileSize',
        );
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partialFile.rename(filePath);

      print('Download completed: ${task.title} (${_formatFileSize(fileSize)})');

      // Mark as completed with actual file size
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.bytesDownloaded = fileSize;
      task.totalBytes = fileSize;
      task.errorMessage = null;
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
      final partialPath = _getPartialSongFilePath(task.songId);
      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        task.bytesDownloaded = await partialFile.length();
      }
      _activeDownloadCount--;
      _handleDownloadError(task, Exception('Unknown error: $e'));
    }
  }

  Future<bool> _downloadTaskWithNativeService({
    required DownloadTask task,
    required String downloadUrl,
    required String filePath,
  }) async {
    if (task.nativeTaskId == null) {
      final startResult = await _nativeDownloadService.startDownload(
        taskId: task.id,
        url: downloadUrl,
        destinationPath: filePath,
        title: task.title,
        totalBytes: task.totalBytes,
      );
      if (startResult == null) {
        return false;
      }

      task.nativeBackend = startResult.backend;
      task.nativeTaskId = startResult.nativeTaskId;
      _queue.updateTask(task);
    }

    await _pollNativeDownload(task, filePath);
    return true;
  }

  Future<void> _pollNativeDownload(DownloadTask task, String filePath) async {
    final nativeTaskId = task.nativeTaskId;
    if (nativeTaskId == null) {
      throw StateError('Native download missing native task id');
    }

    while (task.status == DownloadStatus.downloading) {
      final snapshot = await _nativeDownloadService.queryDownload(
        taskId: task.id,
        nativeTaskId: nativeTaskId,
      );

      final downloaded = snapshot.bytesDownloaded;
      final totalBytes = snapshot.totalBytes > 0
          ? snapshot.totalBytes
          : (task.totalBytes > 0 ? task.totalBytes : downloaded);
      if (downloaded > 0) {
        task.bytesDownloaded = downloaded;
      }
      if (totalBytes > 0) {
        task.totalBytes = totalBytes;
        task.progress = downloaded / totalBytes;
      }

      _activeProgress[task.id] = task.progress;
      _progressController.add(DownloadProgress(
        taskId: task.id,
        progress: task.progress,
        bytesDownloaded: task.bytesDownloaded,
        totalBytes: task.totalBytes,
      ));

      if (snapshot.state == NativeDownloadState.completed) {
        final fileSize = await File(filePath).length();
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.bytesDownloaded = fileSize;
        task.totalBytes = fileSize;
        task.errorMessage = null;
        task.nativeBackend = null;
        task.nativeTaskId = null;
        _queue.updateTask(task);

        _progressController.add(DownloadProgress(
          taskId: task.id,
          progress: 1.0,
          bytesDownloaded: fileSize,
          totalBytes: fileSize,
        ));
        break;
      }

      if (snapshot.state == NativeDownloadState.failed ||
          snapshot.state == NativeDownloadState.cancelled ||
          snapshot.state == NativeDownloadState.unavailable) {
        task.nativeBackend = null;
        task.nativeTaskId = null;
        throw Exception(snapshot.errorMessage ?? 'Native download failed');
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    _activeDownloads.remove(task.id);
    _activeProgress.remove(task.id);
    _activeDownloadCount--;
    await Future.delayed(const Duration(milliseconds: 50));
    _fillDownloadSlots();

    if (task.status == DownloadStatus.completed) {
      unawaited(_cacheArtworkForDownload(task));
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
        if (task.nativeTaskId != null) continue;
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

  int? _parseTotalBytesFromContentRange(String? contentRange) {
    if (contentRange == null || contentRange.isEmpty) {
      return null;
    }
    final slash = contentRange.lastIndexOf('/');
    if (slash <= 0 || slash >= contentRange.length - 1) {
      return null;
    }
    return int.tryParse(contentRange.substring(slash + 1));
  }
}
