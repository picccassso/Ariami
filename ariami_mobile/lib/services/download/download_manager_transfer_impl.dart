part of 'download_manager.dart';

/// Minimum interval between progress events emitted per task. Byte counters on
/// the task update every chunk; only the stream emission is throttled so the
/// main isolate isn't flooded at network-chunk cadence.
const Duration _progressEmitInterval = Duration(milliseconds: 150);

/// How long a transfer may go without receiving a single byte before it is
/// treated as stalled.
///
/// Nothing below this layer notices a connection that stops delivering without
/// erroring — dio's `receiveTimeout` only bounds the wait for response headers,
/// not the body stream — so a half-open socket (the phone leaving Wi-Fi range,
/// a Tailscale route flip) would otherwise hold its slot forever with the
/// progress bar frozen and no error for the retry path to act on. Generous
/// enough that a slow link never trips it; the transfer resumes from its
/// `.partial` file on the retry, so a false positive costs nothing.
const Duration _downloadStallTimeout = Duration(seconds: 60);

extension _DownloadManagerTransferImpl on DownloadManager {
  /// Active-slot ceiling: the server's advertised per-user limit, halved to at
  /// most 2 when cooler downloads mode is on.
  int get _effectiveMaxConcurrentDownloads => _coolerDownloadsEnabled
      ? math.min(coolerModeMaxConcurrentDownloads, _maxConcurrentDownloads)
      : _maxConcurrentDownloads;

  /// Rest between a completed transfer and refilling its slot. The default
  /// only lets state settle; cooler mode inserts a deliberate duty-cycle gap
  /// so the radio and flash are not saturated continuously during bulk
  /// downloads (per-file micro-delays do nothing while all slots stay busy).
  Duration get _slotRefillRest => _coolerDownloadsEnabled
      ? coolerModeSlotRefillRest
      : const Duration(milliseconds: 50);

  DownloadTask? _getNextPendingScoped() {
    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();
    final scopeIds = serverId != null ? _currentServerScopeIds() : null;
    for (final task in _queue.queue) {
      if (task.status != DownloadStatus.pending) continue;
      if (scopeIds != null &&
          (task.serverId == null || !scopeIds.contains(task.serverId))) {
        continue;
      }
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
      while (_slotHolders.length < _effectiveMaxConcurrentDownloads) {
        final nextTask = _getNextPendingScoped();
        if (nextTask == null) {
          if (_slotHolders.isEmpty) {
            print('No more pending downloads');
          }
          return;
        }

        // Mark as downloading BEFORE claiming the slot to prevent double-pickup
        nextTask.status = DownloadStatus.downloading;
        _queue.updateTask(nextTask);

        _slotHolders.add(nextTask.id);
        _downloadTask(nextTask);
      }
    } finally {
      _queue.endBatch();
    }
  }

  /// Release [taskId]'s concurrency slot. Safe to call more than once, and
  /// safe to call for a task that never held one.
  void _releaseSlot(String taskId) {
    _slotHolders.remove(taskId);
  }

  /// Download a specific task
  Future<void> _downloadTask(DownloadTask task) async {
    final totalStopwatch = Stopwatch()..start();
    var backend = 'dart_dio';
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
      if (_shouldUseNativeDownload(task)) {
        backend = 'native_${task.nativeBackend ?? 'android_workmanager'}';
        if (await _downloadTaskWithNativeService(
          task: task,
          downloadUrl: downloadUrl,
          filePath: filePath,
          stopwatch: totalStopwatch,
        )) {
          return;
        }
      }

      final partialFile = File(partialPath);
      final finalFile = File(filePath);
      var resumeOffset =
          await partialFile.exists() ? await partialFile.length() : 0;
      final requestedRange = resumeOffset > 0;

      final headers = <String, String>{};
      if (requestedRange) {
        headers[HttpHeaders.rangeHeader] = 'bytes=$resumeOffset-';
        // If-Range (RFC 9110): the server serves the whole body with 200
        // instead of the range when the file no longer matches this
        // validator, so a resume can never splice bytes of two different
        // versions of the file. A same-length replacement is exactly the case
        // the Content-Range total check below cannot catch on its own.
        final etag = task.downloadEtag;
        if (etag != null && etag.isNotEmpty) {
          headers[HttpHeaders.ifRangeHeader] = etag;
        }
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

      // A 200 to a range request means the range did not apply — either the
      // If-Range validator no longer matches or the server does not do ranges.
      // Either way the full body is coming and the old partial is void.
      if (requestedRange && response.statusCode == 200 && resumeOffset > 0) {
        await partialFile.delete();
        resumeOffset = 0;
      }

      // Remember the validator this body was served with, so the next attempt
      // can resume against it. Null when the server withheld one (a
      // per-request transcode), which correctly clears any stale value.
      task.downloadEtag = response.headers.value(HttpHeaders.etagHeader);

      final writeMode =
          resumeOffset > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly;
      // A RandomAccessFile with awaited writes applies backpressure: the
      // stream is paused while a chunk is being flushed to disk, so the
      // network can never outrun storage and balloon memory the way an
      // unbounded IOSink buffer can with many concurrent downloads.
      final raf = await partialFile.open(mode: writeMode);
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
      final emitStopwatch = Stopwatch()..start();
      var lastEmitMs = -_progressEmitInterval.inMilliseconds;
      // Idle watchdog: the timer restarts on every chunk, so this fires only
      // when the connection goes quiet without closing. Cancelling the token
      // tears the socket down rather than leaving it parked, and the error
      // unwinds into the normal retry path, which resumes from the partial.
      final stalledStream = response.data!.stream.timeout(
        _downloadStallTimeout,
        onTimeout: (sink) {
          cancelToken.cancel('download-stalled');
          sink.addError(
            TimeoutException(
              'Download stalled: no data for '
              '${_downloadStallTimeout.inSeconds}s',
              _downloadStallTimeout,
            ),
          );
          sink.close();
        },
      );
      try {
        await for (final chunk in stalledStream) {
          await raf.writeFrom(chunk);
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

          final elapsedMs = emitStopwatch.elapsedMilliseconds;
          if (elapsedMs - lastEmitMs <
              _progressEmitInterval.inMilliseconds) {
            continue;
          }
          lastEmitMs = elapsedMs;
          _progressController.add(DownloadProgress(
            taskId: task.id,
            progress: task.progress,
            bytesDownloaded: downloaded,
            totalBytes: task.totalBytes,
          ));
        }
      } finally {
        await raf.close();
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
      _logDownloadThroughput(
        backend: backend,
        task: task,
        bytes: fileSize,
        elapsed: totalStopwatch.elapsed,
      );

      // Mark as completed with actual file size
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.bytesDownloaded = fileSize;
      task.totalBytes = fileSize;
      task.errorMessage = null;
      task.downloadEtag = null;
      _queue.updateTask(task); // Update queue on status change

      _progressController.add(DownloadProgress(
        taskId: task.id,
        progress: 1.0,
        bytesDownloaded: fileSize,
        totalBytes: fileSize,
      ));

      _activeDownloads.remove(task.id);
      _activeProgress.remove(task.id); // Cleanup progress tracking

      // Release the slot and fill whatever that frees up
      _releaseSlot(task.id);
      await Future.delayed(_slotRefillRest);
      _fillDownloadSlots();

      // Cache artwork after completion so network/disk prefetch doesn't block
      // download throughput or queue status updates.
      _queueArtworkCaching(task);
    } on DioException catch (e) {
      _releaseSlot(task.id);
      _handleDownloadError(task, e);
    } catch (e) {
      final partialPath = _getPartialSongFilePath(task.songId);
      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        task.bytesDownloaded = await partialFile.length();
      }
      _releaseSlot(task.id);
      _handleDownloadError(task, Exception('Unknown error: $e'));
    } finally {
      // Backstop for any path that unwinds without releasing above — notably
      // a throw from the post-completion work, which used to land in the
      // generic catch and decrement the count a second time.
      _releaseSlot(task.id);
    }
  }

  Future<bool> _downloadTaskWithNativeService({
    required DownloadTask task,
    required String downloadUrl,
    required String filePath,
    required Stopwatch stopwatch,
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
      print(
          '[DownloadManager] Using native download backend ${startResult.backend} for ${task.title}');
      _queue.updateTask(task);
    }

    await _pollNativeDownload(task, filePath, stopwatch: stopwatch);
    return true;
  }

  Future<void> _pollNativeDownload(
    DownloadTask task,
    String filePath, {
    Stopwatch? stopwatch,
  }) async {
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
        final elapsed = stopwatch?.elapsed;
        final nativeBackend = task.nativeBackend ?? 'android_workmanager';
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
        if (elapsed != null) {
          _logDownloadThroughput(
            backend: 'native_$nativeBackend',
            task: task,
            bytes: fileSize,
            elapsed: elapsed,
          );
        }
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
    _releaseSlot(task.id);
    await Future.delayed(_slotRefillRest);
    _fillDownloadSlots();

    if (task.status == DownloadStatus.completed) {
      _queueArtworkCaching(task);
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

    final terminalMessage = _terminalDownloadFailureMessage(error);
    if (terminalMessage != null) {
      task.status = DownloadStatus.failed;
      task.errorMessage = terminalMessage;
      _queue.updateTask(task);
      print('Download failed permanently (not retryable): ${task.title}');

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

  /// Hand active in-app (dio) transfers to the native background backend so
  /// downloads keep running after the app leaves the foreground.
  ///
  /// Android only. Each active dio transfer is paused with a transient
  /// handoff marker (so its cancellation unwinds as expected and releases the
  /// concurrency slot), then re-queued as pending; because the app is no
  /// longer in the foreground, [_fillDownloadSlots] restarts it on the
  /// WorkManager backend, resuming from the shared `.partial` file. The
  /// worker's dataSync foreground service keeps the process — and with it
  /// this queue loop — alive, so pending tasks keep draining too.
  ///
  /// Returns the number of transfers handed off; 0 when the native backend is
  /// unavailable (callers should fall back to pausing).
  Future<int> _continueDownloadsInBackgroundImpl() async {
    if (!_initialized || !Platform.isAndroid) return 0;
    if (!await _nativeDownloadService.isAvailable()) return 0;

    final handedOff = <DownloadTask>[];
    _queue.beginBatch();
    try {
      for (final task in _queue.queue) {
        if (task.status != DownloadStatus.downloading) continue;
        if (task.nativeTaskId != null) continue;
        if (!_activeDownloads.containsKey(task.id)) continue;
        task.status = DownloadStatus.paused;
        task.errorMessage = backgroundHandoffPauseMessage;
        _queue.updateTask(task);
        handedOff.add(task);
      }
    } finally {
      _queue.endBatch();
    }

    for (final task in handedOff) {
      _activeDownloads[task.id]?.cancel('background-handoff');
    }

    if (handedOff.isEmpty) {
      // Nothing to hand off; pending tasks start natively as slots free up.
      _fillDownloadSlots();
      return 0;
    }

    // Let the cancelled transfers unwind and release their slots before the
    // tasks are re-queued for the native backend.
    await Future.delayed(const Duration(milliseconds: 250));

    _queue.beginBatch();
    try {
      for (final task in handedOff) {
        if (task.status != DownloadStatus.paused ||
            task.errorMessage != backgroundHandoffPauseMessage) {
          continue;
        }
        task.status = DownloadStatus.pending;
        task.errorMessage = null;
        _queue.updateTask(task);
      }
    } finally {
      _queue.endBatch();
    }
    _fillDownloadSlots();
    print(
        '[DownloadManager] Handed ${handedOff.length} download(s) to the native background backend');
    return handedOff.length;
  }

  void _pauseScopedDownloadsForInterruption({
    String reasonMessage = interruptedDownloadPauseMessage,
  }) {
    final taskIdsToCancel = <String>[];
    final tasksToPause = <DownloadTask>[];
    final serverId = _getCurrentServerId();
    final userId = _getCurrentUserId();
    final scopeIds = serverId != null ? _currentServerScopeIds() : null;

    for (final task in _queue.queue) {
      if (scopeIds != null &&
          (task.serverId == null || !scopeIds.contains(task.serverId))) {
        continue;
      }
      if (userId != null && task.userId != userId) continue;
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

    _queue.beginBatch();
    try {
      for (final task in tasksToPause) {
        task.status = DownloadStatus.paused;
        task.errorMessage = reasonMessage;
        _queue.updateTask(task);
      }
    } finally {
      _queue.endBatch();
    }

    for (final taskId in taskIdsToCancel) {
      _activeDownloads[taskId]?.cancel('connection-lost');
    }
  }

  /// A message for a failure no amount of retrying can fix, or null when the
  /// error is worth another attempt.
  ///
  /// Retrying these cost 3 attempts and 15s each and always ended in the same
  /// failure — which adds up on a library that has drifted, where every song
  /// deleted server-side is one of these.
  String? _terminalDownloadFailureMessage(dynamic error) {
    if (error is! DioException) return null;
    switch (error.response?.statusCode) {
      case 400:
        return 'The server rejected this download request';
      case 403:
        return 'The server refused this download';
      case 404:
      case 410:
        return 'This song is no longer in the library';
      default:
        // Everything else — 429, 500, 503, and every network failure — can
        // still come good on a retry. 401 is deliberately left retryable: a
        // lapsed session can be restored between attempts.
        return null;
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

  bool _shouldUseNativeDownload(DownloadTask task) {
    if (task.nativeTaskId != null) {
      return true;
    }

    if (Platform.isAndroid) {
      return !_isAppInForeground;
    }

    return true;
  }

  void _logDownloadThroughput({
    required String backend,
    required DownloadTask task,
    required int bytes,
    required Duration elapsed,
  }) {
    final seconds = elapsed.inMilliseconds / 1000.0;
    if (seconds <= 0) return;

    final mb = bytes / (1024 * 1024);
    final mbps = mb / seconds;
    print(
      '[DownloadManager] Download throughput: '
      'backend=$backend '
      'songId=${task.songId} '
      'bytes=$bytes '
      'duration=${seconds.toStringAsFixed(2)}s '
      'speed=${mbps.toStringAsFixed(2)}MB/s',
    );
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
