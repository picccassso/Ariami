import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../models/quality_preset.dart';

part 'src/transcoding_service_environment.dart';
part 'src/transcoding_service_process.dart';
part 'src/transcoding_service_cache.dart';
part 'src/transcoding_service_models.dart';

/// Identifies whether a transcode was requested for streaming or download.
enum TranscodeRequestType {
  streaming,
  download,
}

/// Service for transcoding audio files to different quality levels.
///
/// Uses FFmpeg for transcoding and maintains a cache of transcoded files
/// to avoid re-transcoding on subsequent requests.
///
/// Features:
/// - Separate streaming/download concurrency limits to prevent CPU saturation
/// - JSON-based cache index for fast LRU eviction
/// - Failure backoff to skip repeatedly failing files
/// - Streaming transcode for immediate playback
/// - ffprobe-based fast-path to skip unnecessary transcodes
class TranscodingService {
  /// Base directory for transcoded file cache
  final String cacheDirectory;

  /// Maximum cache size in bytes
  final int maxCacheSizeBytes;

  /// Maximum concurrent transcodes allowed
  final int maxConcurrency;

  /// Maximum concurrent transcodes allowed for download requests
  final int maxDownloadConcurrency;

  /// Timeout for each transcode operation
  final Duration transcodeTimeout;

  /// How long to skip retries after a failure
  final Duration failureBackoffDuration;

  /// Interval between cache index persist operations
  final Duration indexPersistInterval;

  /// Whether FFmpeg is available on this system
  bool? _ffmpegAvailable;

  /// Whether ffprobe is available on this system
  bool? _ffprobeAvailable;

  /// Lock to prevent concurrent transcoding of the same file
  final Map<String, Completer<File?>> _transcodingLocks = {};

  /// Currently running streaming transcode count
  int _runningStreamingCount = 0;

  /// Currently running download transcode count
  int _runningDownloadCount = 0;

  /// Queue of pending streaming transcode tasks
  final Queue<_TranscodeTask> _streamingQueue = Queue();

  /// Queue of pending download transcode tasks
  final Queue<_TranscodeTask> _downloadQueue = Queue();

  /// Cache index: key -> entry
  final Map<String, _CacheIndexEntry> _cacheIndex = {};

  /// Total cached bytes (tracked in memory)
  int _cachedTotalSize = 0;

  /// Whether index needs to be persisted
  bool _indexDirty = false;

  /// Whether index has been loaded
  bool _indexLoaded = false;

  /// Timer for periodic index persistence
  Timer? _persistTimer;

  /// Failure records: lockKey -> record
  final Map<String, _FailureRecord> _failures = {};

  /// In-use cache entries (prevents eviction while streaming)
  final Set<String> _inUse = {};

  /// Cached audio codec selection (detected once at init)
  String? _cachedAudioCodec;

  /// Whether codec detection has been performed
  bool _codecDetected = false;

  /// Creates a new TranscodingService.
  ///
  /// [cacheDirectory] - Base directory for storing transcoded files.
  /// [maxCacheSizeMB] - Maximum cache size in megabytes (default 2048 = 2GB).
  /// [maxConcurrency] - Maximum concurrent streaming transcodes (default 1 for Pi).
  /// [maxDownloadConcurrency] - Maximum concurrent download transcodes (default = maxConcurrency).
  /// [transcodeTimeout] - Timeout per transcode (default 5 minutes).
  /// [failureBackoffDuration] - How long to skip after failure (default 5 minutes).
  /// [indexPersistInterval] - Interval for persisting cache index (default 30 seconds).
  TranscodingService({
    required this.cacheDirectory,
    int maxCacheSizeMB = 2048,
    this.maxConcurrency = 1,
    int? maxDownloadConcurrency,
    this.transcodeTimeout = const Duration(minutes: 5),
    this.failureBackoffDuration = const Duration(minutes: 5),
    this.indexPersistInterval = const Duration(seconds: 30),
  })  : maxCacheSizeBytes = maxCacheSizeMB * 1024 * 1024,
        maxDownloadConcurrency = maxDownloadConcurrency ?? maxConcurrency {
    _startPersistTimer();
  }

  /// Dispose resources. Call when shutting down.
  void dispose() {
    _persistTimer?.cancel();
    if (_indexDirty) {
      _persistCacheIndexSync();
    }
  }

  /// Start periodic index persistence timer.
  void _startPersistTimer() {
    _persistTimer?.cancel();
    _persistTimer = Timer.periodic(indexPersistInterval, (_) {
      if (_indexDirty) {
        _persistCacheIndex();
      }
    });
  }

  /// Check if FFmpeg is available on the system.
  Future<bool> isFFmpegAvailable() => _isFFmpegAvailable();

  /// Get a transcoded file for the given source and quality.
  ///
  /// Returns the transcoded file if it exists in cache or after transcoding.
  /// Returns null if:
  /// - Quality is [QualityPreset.high] (no transcoding needed)
  /// - FFmpeg is not available
  /// - Transcoding fails
  /// - Source bitrate is already at or below target (fast-path)
  ///
  /// [sourcePath] - Path to the original audio file.
  /// [songId] - Unique identifier for the song (used for cache filename).
  /// [quality] - Target quality preset.
  Future<File?> getTranscodedFile(
    String sourcePath,
    String songId,
    QualityPreset quality, {
    TranscodeRequestType requestType = TranscodeRequestType.streaming,
  }) async {
    // Keep requestType for API compatibility; downloads should use getDownloadTranscode().
    if (requestType == TranscodeRequestType.download) {
      // No-op: cached transcodes are streaming-only.
    }
    // No transcoding needed for high quality
    if (!quality.requiresTranscoding) {
      return null;
    }

    // Check FFmpeg availability
    if (!await isFFmpegAvailable()) {
      print('TranscodingService: Cannot transcode - FFmpeg not available');
      return null;
    }

    final lockKey = '${songId}_${quality.name}';

    // Check failure backoff
    if (_shouldSkipDueToFailure(lockKey)) {
      final record = _failures[lockKey]!;
      print(
          'TranscodingService: Skipping $lockKey - failed ${record.failureCount}x, '
          'backoff until ${record.lastFailure.add(failureBackoffDuration)}');
      return null;
    }

    // Ensure cache index is loaded
    await _ensureIndexLoaded();

    // Check cache first
    final cachedFile = _getCachedFile(songId, quality);
    if (await cachedFile.exists()) {
      print('TranscodingService: Cache hit for $songId at ${quality.name}');
      // Update access time in memory (no disk write)
      _recordAccess(lockKey);
      return cachedFile;
    } else {
      // File missing but was in index - remove from index
      if (_cacheIndex.containsKey(lockKey)) {
        _removeFromIndex(lockKey);
      }
    }

    // Fast-path: check if source bitrate is already low enough
    final props = await _getAudioProperties(sourcePath);
    if (props != null && props.shouldSkipTranscode(quality)) {
      print('TranscodingService: Skipping transcode - source bitrate '
          '(${props.bitrate! ~/ 1000} kbps) <= target (${quality.bitrate} kbps)');
      return null; // Signal to serve original file
    }

    // Check if already transcoding this specific file
    if (_transcodingLocks.containsKey(lockKey)) {
      print('TranscodingService: Waiting for existing transcode of $songId');
      return await _transcodingLocks[lockKey]!.future;
    }

    // Cached transcodes are for streaming only. Downloads use getDownloadTranscode().
    final runningCount = _runningStreamingCount;
    final maxForType = maxConcurrency;
    final taskQueue = _streamingQueue;
    final typeLabel = 'streaming';

    // Check concurrency for this request type - queue if at limit
    if (runningCount >= maxForType) {
      print('TranscodingService: Queuing $songId for $typeLabel '
          '(running: $runningCount, max: $maxForType)');
      final task = _TranscodeTask(
        sourcePath: sourcePath,
        songId: songId,
        quality: quality,
        completer: Completer<File?>(),
      );
      taskQueue.add(task);
      return await task.completer.future;
    }

    // Start transcoding with lock
    final completer = Completer<File?>();
    _transcodingLocks[lockKey] = completer;
    _runningStreamingCount++;

    try {
      print('TranscodingService: Transcoding $songId to ${quality.name} '
          '($typeLabel running: $_runningStreamingCount, '
          'queued: ${taskQueue.length})');
      final result = await _transcodeFile(sourcePath, cachedFile.path, quality);

      if (result != null) {
        // Add to cache index
        final size = await result.length();
        _addToIndex(
            lockKey, '${quality.name}/$songId.${quality.fileExtension}', size);

        // Clear any previous failure
        _clearFailure(lockKey);

        // Cleanup cache if needed (async, don't wait)
        _cleanupCacheIfNeeded();
      } else {
        _recordFailure(lockKey, 'Transcode returned null');
      }

      completer.complete(result);
      return result;
    } catch (e) {
      print('TranscodingService: Transcode error - $e');
      _recordFailure(lockKey, e.toString());
      completer.complete(null);
      return null;
    } finally {
      _transcodingLocks.remove(lockKey);
      _runningStreamingCount--;
      _processNextStreamingQueue();
      _processNextDownloadQueue();
    }
  }

  /// Process next streaming task in queue if capacity available.
  void _processNextStreamingQueue() {
    if (_streamingQueue.isEmpty || _runningStreamingCount >= maxConcurrency) {
      return;
    }

    final task = _streamingQueue.removeFirst();
    // Re-invoke getTranscodedFile for the queued task (streaming cache)
    getTranscodedFile(
      task.sourcePath,
      task.songId,
      task.quality,
      requestType: TranscodeRequestType.streaming,
    ).then((file) => task.completer.complete(file)).catchError((e) {
      print('TranscodingService: Queued streaming task error - $e');
      task.completer.complete(null);
    });
  }

  /// Process next download task in queue if capacity available.
  void _processNextDownloadQueue() {
    if (_downloadQueue.isEmpty ||
        _runningDownloadCount >= maxDownloadConcurrency) {
      return;
    }

    final task = _downloadQueue.removeFirst();
    _runDownloadQueueTask(task);
  }

  Future<void> _runDownloadQueueTask(_TranscodeTask task) async {
    _runningDownloadCount++;
    final lockKey = '${task.songId}_${task.quality.name}_download';

    try {
      final result = await _performDownloadTranscode(
        task.sourcePath,
        task.songId,
        task.quality,
        lockKey,
      );
      task.completer.complete(result);
    } catch (e) {
      print('TranscodingService: Queued download task error - $e');
      task.completer.complete(null);
    } finally {
      _runningDownloadCount--;
      _processNextDownloadQueue();
    }
  }

  /// Transcode a file for download without adding to the shared cache.
  ///
  /// This method creates a temporary file that should be deleted by the caller
  /// after the download completes. This prevents cache churn during bulk
  /// downloads and avoids eviction races.
  ///
  /// Returns a [DownloadTranscodeResult] containing the temp file path,
  /// or null if transcoding fails or is not needed.
  Future<DownloadTranscodeResult?> getDownloadTranscode(
    String sourcePath,
    String songId,
    QualityPreset quality,
  ) async {
    // No transcoding needed for high quality
    if (!quality.requiresTranscoding) {
      return null;
    }

    // Check FFmpeg availability
    if (!await isFFmpegAvailable()) {
      print(
          'TranscodingService: Cannot transcode for download - FFmpeg not available');
      return null;
    }

    final lockKey = '${songId}_${quality.name}_download';

    // Check failure backoff
    if (_shouldSkipDueToFailure(lockKey)) {
      print(
          'TranscodingService: Skipping download transcode $lockKey - in backoff');
      return null;
    }

    // Fast-path: check if source bitrate is already low enough
    final props = await _getAudioProperties(sourcePath);
    if (props != null && props.shouldSkipTranscode(quality)) {
      print('TranscodingService: Skipping download transcode - source bitrate '
          '(${props.bitrate! ~/ 1000} kbps) <= target (${quality.bitrate} kbps)');
      return null;
    }

    // Check download concurrency - queue if at limit
    if (_runningDownloadCount >= maxDownloadConcurrency) {
      print('TranscodingService: Queuing download transcode $songId '
          '(running: $_runningDownloadCount, max: $maxDownloadConcurrency)');
      final task = _TranscodeTask(
        sourcePath: sourcePath,
        songId: songId,
        quality: quality,
        completer: Completer<File?>(),
      );
      _downloadQueue.add(task);
      final result = await task.completer.future;
      if (result != null) {
        return DownloadTranscodeResult(tempFile: result, shouldDelete: true);
      }
      return null;
    }

    _runningDownloadCount++;

    try {
      final result = await _performDownloadTranscode(
        sourcePath,
        songId,
        quality,
        lockKey,
      );
      if (result != null) {
        return DownloadTranscodeResult(tempFile: result, shouldDelete: true);
      }
      return null;
    } finally {
      _runningDownloadCount--;
      _processNextDownloadQueue();
    }
  }

  /// Mark a cache entry as in-use to prevent eviction during streaming.
  ///
  /// Call [releaseInUse] when streaming is complete.
  void markInUse(String songId, QualityPreset quality) {
    _markInUse(songId, quality);
  }

  /// Release a cache entry from in-use status.
  ///
  /// Should be called after streaming completes.
  void releaseInUse(String songId, QualityPreset quality) {
    _releaseInUse(songId, quality);
  }

  /// Get current cache size in bytes (from index, no disk scan).
  Future<int> getCacheSize() => _getCacheSize();

  /// Clear the entire transcoding cache.
  Future<void> clearCache() => _clearCache();

  /// Delete cached transcodes for a specific song.
  ///
  /// Useful when the source file changes.
  Future<void> invalidateSong(String songId) => _invalidateSong(songId);
}
