import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:path/path.dart' as p;
import '../../models/quality_preset.dart';

part 'src/transcoding_service_environment.dart';
part 'src/transcoding_service_process.dart';
part 'src/transcoding_service_cache.dart';
part 'src/transcoding_service_models.dart';
part 'src/transcoding_service_ffi.dart';

/// Identifies whether a transcode was requested for streaming or download.
enum TranscodeRequestType {
  streaming,
  download,
}

/// Container/codec produced by Sonic for a transcoded download.
///
/// Streaming continues to use AAC unless a future protocol revision explicitly
/// negotiates another format. Downloads negotiate this independently so newer
/// clients can request Opus or M4A without changing older clients' behaviour.
enum TranscodeOutputFormat {
  aac,
  m4a,
  opus;

  String get fileExtension => name;

  String get mimeType => switch (this) {
        TranscodeOutputFormat.aac => 'audio/aac',
        TranscodeOutputFormat.m4a => 'audio/mp4',
        TranscodeOutputFormat.opus => 'audio/ogg; codecs=opus',
      };

  int get _sonicValue => switch (this) {
        TranscodeOutputFormat.aac => 0,
        TranscodeOutputFormat.m4a => 2,
        TranscodeOutputFormat.opus => 3,
      };

  static TranscodeOutputFormat? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return switch (normalized) {
      'aac' => TranscodeOutputFormat.aac,
      'm4a' => TranscodeOutputFormat.m4a,
      'opus' => TranscodeOutputFormat.opus,
      _ => null,
    };
  }
}

/// Service for transcoding audio files to different quality levels.
///
/// Uses Sonic for MP3 -> AAC transcoding and maintains a cache of transcoded files
/// to avoid re-transcoding on subsequent requests.
///
/// Features:
/// - Separate streaming/download concurrency limits to prevent CPU saturation
/// - JSON-based cache index for fast LRU eviction
/// - Failure backoff to skip repeatedly failing files
/// - Streaming transcode for immediate playback
/// - ffprobe-based fast-path to skip unnecessary transcodes
class TranscodingService {
  final String cacheDirectory;

  final int maxCacheSizeBytes;

  final int maxConcurrency;

  final int maxDownloadConcurrency;

  final Duration transcodeTimeout;

  /// How long to skip retries after a failure
  final Duration failureBackoffDuration;

  final Duration indexPersistInterval;

  /// Optional explicit path to Sonic's dynamic library.
  final String? sonicLibraryPath;

  _SonicFfiAdapter? _sonicFfiAdapter;

  bool? _ffprobeAvailable;

  /// Lock to prevent concurrent transcoding of the same file
  final Map<String, Completer<File?>> _transcodingLocks = {};

  int _runningStreamingCount = 0;

  int _runningDownloadCount = 0;

  final Queue<_TranscodeTask> _streamingQueue = Queue();

  final Queue<_TranscodeTask> _downloadQueue = Queue();

  final Queue<_TranscodeTask> _warmupQueue = Queue();
  final Set<String> _queuedWarmups = {};
  int _runningWarmupCount = 0;

  final Map<String, _CacheIndexEntry> _cacheIndex = {};

  /// Total cached bytes (tracked in memory)
  int _cachedTotalSize = 0;

  bool _indexDirty = false;

  bool _indexLoaded = false;

  Timer? _persistTimer;

  final Map<String, _FailureRecord> _failures = {};

  /// In-use cache entries (prevents eviction while streaming)
  final Set<String> _inUse = {};

  /// Creates a new TranscodingService.
  ///
  /// [cacheDirectory] - Base directory for storing transcoded files.
  /// [maxCacheSizeMB] - Maximum cache size in megabytes (default 2048 = 2GB).
  /// [maxConcurrency] - Maximum concurrent streaming transcodes (derived from the platform default: 3 on Pi 3, 4 on Pi 4, 5 on Pi 5, 6 elsewhere).
  /// [maxDownloadConcurrency] - Maximum concurrent download transcodes (defaults to [maxConcurrency]).
  /// [transcodeTimeout] - Timeout per transcode (default 5 minutes).
  /// [failureBackoffDuration] - How long to skip after failure (default 5 minutes).
  /// [indexPersistInterval] - Interval for persisting cache index (default 30 seconds).
  /// [sonicLibraryPath] - Optional explicit path to the Sonic dynamic library.
  TranscodingService({
    required this.cacheDirectory,
    int maxCacheSizeMB = 2048,
    this.maxConcurrency = 1,
    int? maxDownloadConcurrency,
    this.transcodeTimeout = const Duration(minutes: 5),
    this.failureBackoffDuration = const Duration(minutes: 5),
    this.indexPersistInterval = const Duration(seconds: 30),
    this.sonicLibraryPath,
  })  : maxCacheSizeBytes = maxCacheSizeMB * 1024 * 1024,
        maxDownloadConcurrency = maxDownloadConcurrency ?? maxConcurrency {
    _startPersistTimer();
  }

  void dispose() {
    _persistTimer?.cancel();
    if (_indexDirty) {
      _persistCacheIndexSync();
    }
  }

  void _startPersistTimer() {
    _persistTimer?.cancel();
    _persistTimer = Timer.periodic(indexPersistInterval, (_) {
      if (_indexDirty) {
        _persistCacheIndex();
      }
    });
  }

  Future<bool> isSonicAvailable() => _isSonicAvailable();

  /// Get a transcoded file for the given source and quality.
  ///
  /// Returns the transcoded file if it exists in cache or after transcoding.
  /// Returns null if:
  /// - Quality is [QualityPreset.high] (no transcoding needed)
  /// - Sonic is not available
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
    int? sourceBitrateKbps,
  }) async {
    // Keep requestType for API compatibility; downloads should use getDownloadTranscode().
    if (requestType == TranscodeRequestType.download) {
      // No-op: cached transcodes are streaming-only.
    }
    if (!quality.requiresTranscoding) {
      return null;
    }

    if (!await isSonicAvailable()) {
      print('TranscodingService: Cannot transcode - Sonic not available');
      return null;
    }

    final lockKey = '${songId}_${quality.name}';

    if (_shouldSkipDueToFailure(lockKey)) {
      final record = _failures[lockKey]!;
      print(
          'TranscodingService: Skipping $lockKey - failed ${record.failureCount}x, '
          'backoff until ${record.lastFailure.add(failureBackoffDuration)}');
      return null;
    }

    await _ensureIndexLoaded();

    final cachedFile = _getCachedFile(songId, quality);
    if (await cachedFile.exists()) {
      print('TranscodingService: Cache hit for $songId at ${quality.name}');
      _recordAccess(lockKey);
      return cachedFile;
    } else {
      if (_cacheIndex.containsKey(lockKey)) {
        _removeFromIndex(lockKey);
      }
    }

    final targetBitrate = quality.bitrate;
    final knownBitrate = sourceBitrateKbps;
    if (knownBitrate != null && knownBitrate > 0 && targetBitrate != null) {
      if (knownBitrate <= targetBitrate) {
        print('TranscodingService: Skipping transcode - known source bitrate '
            '($knownBitrate kbps) <= target ($targetBitrate kbps)');
        return null;
      }
    } else {
      // Fast-path: check if source bitrate is already low enough.
      final props = await _getAudioProperties(sourcePath);
      if (props != null && props.shouldSkipTranscode(quality)) {
        print('TranscodingService: Skipping transcode - source bitrate '
            '(${props.bitrate! ~/ 1000} kbps) <= target (${quality.bitrate} kbps)');
        return null; // Signal to serve original file
      }
    }

    if (_transcodingLocks.containsKey(lockKey)) {
      print('TranscodingService: Waiting for existing transcode of $songId');
      return await _transcodingLocks[lockKey]!.future;
    }

    // Cached transcodes are for streaming only. Downloads use getDownloadTranscode().
    final runningCount = _runningStreamingCount;
    final maxForType = maxConcurrency;
    final taskQueue = _streamingQueue;
    final typeLabel = 'streaming';

    if (runningCount >= maxForType) {
      print('TranscodingService: Queuing $songId for $typeLabel '
          '(running: $runningCount, max: $maxForType)');
      final task = _TranscodeTask(
        sourcePath: sourcePath,
        songId: songId,
        quality: quality,
        completer: Completer<File?>(),
        sourceBitrateKbps: sourceBitrateKbps,
      );
      taskQueue.add(task);
      return await task.completer.future;
    }

    final completer = Completer<File?>();
    _transcodingLocks[lockKey] = completer;
    _runningStreamingCount++;

    try {
      print('TranscodingService: Transcoding $songId to ${quality.name} '
          '($typeLabel running: $_runningStreamingCount, '
          'queued: ${taskQueue.length})');
      final result = await _transcodeFile(sourcePath, cachedFile.path, quality);

      if (result != null) {
        final size = await result.length();
        _addToIndex(
            lockKey, '${quality.name}/$songId.${quality.fileExtension}', size);

        _clearFailure(lockKey);

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
      _processNextWarmupQueue();
    }
  }

  /// Final cache file used by lower-quality streaming.
  ///
  /// Exposed so the HTTP layer can begin a cold stream from Sonic's growing
  /// partial output instead of waiting for the complete song to be transcoded.
  File streamingCacheFile(String songId, QualityPreset quality) =>
      _getCachedFile(songId, quality);

  /// In-progress output paired with [streamingCacheFile]. The file is renamed
  /// atomically to the final path when transcoding completes.
  File streamingPartialFile(String songId, QualityPreset quality) =>
      File('${_getCachedFile(songId, quality).path}.partial');

  void _processNextStreamingQueue() {
    if (_streamingQueue.isEmpty || _runningStreamingCount >= maxConcurrency) {
      return;
    }

    final task = _streamingQueue.removeFirst();
    getTranscodedFile(
      task.sourcePath,
      task.songId,
      task.quality,
      requestType: TranscodeRequestType.streaming,
      sourceBitrateKbps: task.sourceBitrateKbps,
    ).then((file) => task.completer.complete(file)).catchError((e) {
      print('TranscodingService: Queued streaming task error - $e');
      task.completer.complete(null);
    });
  }

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
    final lockKey =
        '${task.songId}_${task.quality.name}_${task.outputFormat.name}_download';

    try {
      final result = await _performDownloadTranscode(
        task.sourcePath,
        task.songId,
        task.quality,
        lockKey,
        task.outputFormat,
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

  /// Queue a low-priority cache warmup for likely upcoming playback.
  ///
  /// Warmups never block the caller and do not run while active streaming
  /// transcodes are using the Pi's limited CPU budget.
  Future<bool> warmTranscodedFile(
    String sourcePath,
    String songId,
    QualityPreset quality, {
    int? sourceBitrateKbps,
  }) async {
    if (!quality.requiresTranscoding) return false;
    if (!await isSonicAvailable()) return false;

    final lockKey = '${songId}_${quality.name}';
    await _ensureIndexLoaded();

    final cachedFile = _getCachedFile(songId, quality);
    if (await cachedFile.exists()) {
      _recordAccess(lockKey);
      return false;
    }
    if (_transcodingLocks.containsKey(lockKey) ||
        _queuedWarmups.contains(lockKey)) {
      return false;
    }
    if (_shouldSkipDueToFailure(lockKey)) return false;

    final task = _TranscodeTask(
      sourcePath: sourcePath,
      songId: songId,
      quality: quality,
      completer: Completer<File?>(),
      sourceBitrateKbps: sourceBitrateKbps,
    );
    _queuedWarmups.add(lockKey);
    _warmupQueue.add(task);
    _processNextWarmupQueue();
    return true;
  }

  void _processNextWarmupQueue() {
    if (_warmupQueue.isEmpty ||
        _runningWarmupCount >= 1 ||
        _runningStreamingCount > 0 ||
        _streamingQueue.isNotEmpty) {
      return;
    }

    final task = _warmupQueue.removeFirst();
    final lockKey = '${task.songId}_${task.quality.name}';
    _queuedWarmups.remove(lockKey);
    _runningWarmupCount++;

    getTranscodedFile(
      task.sourcePath,
      task.songId,
      task.quality,
      requestType: TranscodeRequestType.streaming,
      sourceBitrateKbps: task.sourceBitrateKbps,
    ).then(task.completer.complete).catchError((e) {
      print('TranscodingService: Warmup task error - $e');
      task.completer.complete(null);
    }).whenComplete(() {
      _runningWarmupCount--;
      _processNextWarmupQueue();
    });
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
    QualityPreset quality, {
    TranscodeOutputFormat outputFormat = TranscodeOutputFormat.aac,
  }) async {
    if (!await isSonicAvailable()) {
      print(
          'TranscodingService: Cannot transcode for download - Sonic not available');
      return null;
    }

    final lockKey = '${songId}_${quality.name}_${outputFormat.name}_download';

    if (_shouldSkipDueToFailure(lockKey)) {
      print(
          'TranscodingService: Skipping download transcode $lockKey - in backoff');
      return null;
    }

    // Download requests should produce the requested quality deterministically
    // and avoid per-file ffprobe process overhead in bulk jobs.

    if (_runningDownloadCount >= maxDownloadConcurrency) {
      print('TranscodingService: Queuing download transcode $songId '
          '(running: $_runningDownloadCount, max: $maxDownloadConcurrency)');
      final task = _TranscodeTask(
        sourcePath: sourcePath,
        songId: songId,
        quality: quality,
        outputFormat: outputFormat,
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
        outputFormat,
      );
      if (result != null) {
        return DownloadTranscodeResult(tempFile: result, shouldDelete: true);
      }
      return null;
    } finally {
      _runningDownloadCount--;
      _processNextDownloadQueue();
      _processNextWarmupQueue();
    }
  }

  void markInUse(String songId, QualityPreset quality) {
    _markInUse(songId, quality);
  }

  void releaseInUse(String songId, QualityPreset quality) {
    _releaseInUse(songId, quality);
  }

  Future<int> getCacheSize() => _getCacheSize();

  Future<void> clearCache() => _clearCache();

  Future<void> invalidateSong(String songId) => _invalidateSong(songId);
}
