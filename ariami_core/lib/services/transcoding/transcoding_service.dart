import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../models/quality_preset.dart';

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
  Future<bool> isFFmpegAvailable() async {
    if (_ffmpegAvailable != null) return _ffmpegAvailable!;

    try {
      final result = await Process.run('ffmpeg', ['-version']);
      _ffmpegAvailable = result.exitCode == 0;
      if (_ffmpegAvailable!) {
        print('TranscodingService: FFmpeg is available');
      } else {
        print('TranscodingService: FFmpeg not found (exit code ${result.exitCode})');
      }
    } catch (e) {
      print('TranscodingService: FFmpeg not available - $e');
      _ffmpegAvailable = false;
    }

    return _ffmpegAvailable!;
  }

  /// Check if ffprobe is available on the system.
  Future<bool> _isFFprobeAvailable() async {
    if (_ffprobeAvailable != null) return _ffprobeAvailable!;

    try {
      final result = await Process.run('ffprobe', ['-version']);
      _ffprobeAvailable = result.exitCode == 0;
    } catch (e) {
      _ffprobeAvailable = false;
    }

    return _ffprobeAvailable!;
  }

  /// Get audio properties using ffprobe.
  /// Returns null if ffprobe fails or file can't be analyzed.
  Future<_AudioProperties?> _getAudioProperties(String sourcePath) async {
    if (!await _isFFprobeAvailable()) return null;

    try {
      final result = await Process.run('ffprobe', [
        '-v', 'quiet',
        '-select_streams', 'a:0',
        '-show_entries', 'stream=codec_name,bit_rate,sample_rate',
        '-of', 'json',
        sourcePath,
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode != 0) return null;

      final json = jsonDecode(result.stdout as String);
      final streams = json['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) return null;

      final stream = streams[0] as Map<String, dynamic>;
      return _AudioProperties(
        codec: stream['codec_name'] as String?,
        bitrate: int.tryParse(stream['bit_rate']?.toString() ?? ''),
        sampleRate: int.tryParse(stream['sample_rate']?.toString() ?? ''),
      );
    } catch (e) {
      print('TranscodingService: ffprobe error - $e');
      return null;
    }
  }

  /// Detect and cache the best audio codec for this platform.
  ///
  /// On macOS, prefers `aac_at` (AudioToolbox hardware AAC) if available.
  /// Falls back to software `aac` on all other platforms or if detection fails.
  Future<String> _selectAudioCodec() async {
    if (_codecDetected) return _cachedAudioCodec!;

    _cachedAudioCodec = 'aac'; // Default fallback

    // Only check for hardware encoder on macOS
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('ffmpeg', ['-encoders']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          if (output.contains('aac_at')) {
            _cachedAudioCodec = 'aac_at';
            print('TranscodingService: Using hardware AAC encoder (aac_at) on macOS');
          } else {
            print('TranscodingService: Hardware AAC (aac_at) not available, using software AAC');
          }
        }
      } catch (e) {
        print('TranscodingService: Codec detection failed, using software AAC - $e');
      }
    } else {
      print('TranscodingService: Using software AAC encoder on ${Platform.operatingSystem}');
    }

    _codecDetected = true;
    return _cachedAudioCodec!;
  }

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
      print('TranscodingService: Skipping $lockKey - failed ${record.failureCount}x, '
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
        _addToIndex(lockKey, '${quality.name}/$songId.${quality.fileExtension}', size);

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
    if (_streamingQueue.isEmpty || _runningStreamingCount >= maxConcurrency) return;

    final task = _streamingQueue.removeFirst();
    // Re-invoke getTranscodedFile for the queued task (streaming cache)
    getTranscodedFile(
      task.sourcePath,
      task.songId,
      task.quality,
      requestType: TranscodeRequestType.streaming,
    )
        .then((file) => task.completer.complete(file))
        .catchError((e) {
          print('TranscodingService: Queued streaming task error - $e');
          task.completer.complete(null);
        });
  }

  /// Process next download task in queue if capacity available.
  void _processNextDownloadQueue() {
    if (_downloadQueue.isEmpty || _runningDownloadCount >= maxDownloadConcurrency) return;

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
      print('TranscodingService: Cannot transcode for download - FFmpeg not available');
      return null;
    }

    final lockKey = '${songId}_${quality.name}_download';

    // Check failure backoff
    if (_shouldSkipDueToFailure(lockKey)) {
      print('TranscodingService: Skipping download transcode $lockKey - in backoff');
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

  Future<File?> _performDownloadTranscode(
    String sourcePath,
    String songId,
    QualityPreset quality,
    String lockKey,
  ) async {
    try {
      // Create temp directory if needed
      final tempDir = Directory('$cacheDirectory/tmp');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // Generate unique temp filename
      final random = Random();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomSuffix = random.nextInt(999999).toString().padLeft(6, '0');
      final tempPath = '${tempDir.path}/${songId}_${timestamp}_$randomSuffix.${quality.fileExtension}';

      print('TranscodingService: Download transcode $songId to ${quality.name} '
          '(running: $_runningDownloadCount)');

      final result = await _transcodeFile(sourcePath, tempPath, quality);

      if (result != null) {
        _clearFailure(lockKey);
        return result;
      }

      _recordFailure(lockKey, 'Download transcode returned null');
      return null;
    } catch (e) {
      print('TranscodingService: Download transcode error - $e');
      _recordFailure(lockKey, e.toString());
      return null;
    }
  }

  /// Start a streaming transcode that returns a Stream of bytes.
  ///
  /// Use this for immediate playback without waiting for full transcode.
  /// Returns null if:
  /// - Cached file already exists (use getTranscodedFile instead)
  /// - FFmpeg not available
  /// - At concurrency limit (caller should fall back to queued transcode)
  ///
  /// The returned stream can be piped directly to HTTP response.
  /// The cache file will be populated in the background.
  Future<StreamTranscodeResult?> startStreamingTranscode(
    String sourcePath,
    String songId,
    QualityPreset quality,
  ) async {
    if (!quality.requiresTranscoding) return null;
    if (!await isFFmpegAvailable()) return null;

    final lockKey = '${songId}_${quality.name}';

    // Check failure backoff
    if (_shouldSkipDueToFailure(lockKey)) return null;

    // Ensure cache index is loaded
    await _ensureIndexLoaded();

    // Check cache first - if exists, caller should use getTranscodedFile
    final cachedFile = _getCachedFile(songId, quality);
    if (await cachedFile.exists()) {
      return null;
    }

    // Fast-path: check if source bitrate is already low enough
    final props = await _getAudioProperties(sourcePath);
    if (props != null && props.shouldSkipTranscode(quality)) {
      return null; // Signal to serve original file
    }

    // Check if already transcoding
    if (_transcodingLocks.containsKey(lockKey)) return null;

    // Check streaming concurrency - don't queue streaming requests
    if (_runningStreamingCount >= maxConcurrency) return null;

    // Start streaming transcode
    _runningStreamingCount++;
    final streamCompleter = Completer<File?>();
    _transcodingLocks[lockKey] = streamCompleter;

    try {
      // Ensure output directory exists
      await cachedFile.parent.create(recursive: true);
      final tempFile = File('${cachedFile.path}.tmp');

      // Get platform-aware codec
      final codec = await _selectAudioCodec();

      // Start FFmpeg with fragmented MP4 output for streaming
      final process = await Process.start('ffmpeg', [
        '-y',
        '-i', sourcePath,
        '-c:a', codec,
        '-b:a', '${quality.bitrate}k',
        '-vn',
        '-movflags', 'frag_keyframe+empty_moov',
        '-f', 'mp4',
        'pipe:1',
      ]);

      // Create a broadcast controller to tee output
      final controller = StreamController<List<int>>();
      IOSink? cacheSink;

      try {
        cacheSink = tempFile.openWrite();
      } catch (e) {
        print('TranscodingService: Cannot write cache file - $e');
        // Continue without caching
      }

      print('TranscodingService: Streaming transcode started for $songId');

      process.stdout.listen(
        (chunk) {
          controller.add(chunk);
          cacheSink?.add(chunk);
        },
        onDone: () async {
          controller.close();
          await cacheSink?.flush();
          await cacheSink?.close();

          final exitCode = await process.exitCode;
          if (exitCode == 0 && await tempFile.exists()) {
            try {
              await tempFile.rename(cachedFile.path);
              final size = await cachedFile.length();
              _addToIndex(lockKey, '${quality.name}/$songId.${quality.fileExtension}', size);
              _clearFailure(lockKey);
              print('TranscodingService: Streaming transcode cached - ${(size / 1024).round()} KB');
              streamCompleter.complete(cachedFile);
              _cleanupCacheIfNeeded();
            } catch (e) {
              try { await tempFile.delete(); } catch (_) {}
              streamCompleter.complete(null);
            }
          } else {
            try { await tempFile.delete(); } catch (_) {}
            _recordFailure(lockKey, 'FFmpeg exit code: $exitCode');
            streamCompleter.complete(null);
          }

          _transcodingLocks.remove(lockKey);
          _runningStreamingCount--;
          _processNextStreamingQueue();
          _processNextDownloadQueue();
        },
        onError: (e) {
          controller.addError(e);
          controller.close();
          cacheSink?.close();
          tempFile.delete().ignore();
          _recordFailure(lockKey, e.toString());
          streamCompleter.complete(null);
          _transcodingLocks.remove(lockKey);
          _runningStreamingCount--;
          _processNextStreamingQueue();
          _processNextDownloadQueue();
        },
      );

      // Log stderr for debugging
      process.stderr.transform(utf8.decoder).listen((msg) {
        // Only log errors, not progress
        if (msg.contains('Error') || msg.contains('error')) {
          print('TranscodingService: FFmpeg stderr - $msg');
        }
      });

      return StreamTranscodeResult(
        stream: controller.stream,
        cacheFile: streamCompleter.future,
        mimeType: quality.mimeType ?? 'audio/mp4',
      );
    } catch (e) {
      print('TranscodingService: Streaming transcode error - $e');
      _recordFailure(lockKey, e.toString());
      _transcodingLocks.remove(lockKey);
      _runningStreamingCount--;
      streamCompleter.complete(null);
      return null;
    }
  }

  /// Get the cached file path for a song at a specific quality.
  File _getCachedFile(String songId, QualityPreset quality) {
    final qualityDir = Directory('$cacheDirectory/${quality.name}');
    return File('${qualityDir.path}/$songId.${quality.fileExtension}');
  }

  /// Transcode a file using FFmpeg.
  Future<File?> _transcodeFile(
    String sourcePath,
    String outputPath,
    QualityPreset quality,
  ) async {
    // Ensure output directory exists
    final outputDir = Directory(outputPath).parent;
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Build FFmpeg command (async for platform-aware codec detection)
    final args = await _buildFFmpegArgs(sourcePath, outputPath, quality);

    print('TranscodingService: Running ffmpeg ${args.join(' ')}');

    try {
      final result = await Process.run(
        'ffmpeg',
        args,
      ).timeout(
        transcodeTimeout,
        onTimeout: () {
          print('TranscodingService: Transcode timeout after ${transcodeTimeout.inMinutes} minutes');
          return ProcessResult(-1, -1, '', 'Timeout');
        },
      );

      if (result.exitCode == 0) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          print('TranscodingService: Transcode complete - ${(size / 1024).round()} KB');
          return outputFile;
        }
      }

      print('TranscodingService: FFmpeg failed (exit ${result.exitCode})');
      print('TranscodingService: stderr: ${result.stderr}');

      // Clean up partial file if it exists
      final partialFile = File(outputPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      return null;
    } catch (e) {
      print('TranscodingService: FFmpeg error - $e');

      // Clean up partial file
      try {
        final partialFile = File(outputPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) {}

      return null;
    }
  }

  /// Build FFmpeg arguments for transcoding.
  ///
  /// Uses platform-aware codec selection:
  /// - macOS: `aac_at` (AudioToolbox hardware AAC) if available
  /// - Other platforms: software `aac`
  Future<List<String>> _buildFFmpegArgs(
    String sourcePath,
    String outputPath,
    QualityPreset quality,
  ) async {
    final bitrate = quality.bitrate;
    if (bitrate == null) {
      throw ArgumentError('Cannot build FFmpeg args for high quality');
    }

    // Get platform-aware codec
    final codec = await _selectAudioCodec();

    return [
      '-y', // Overwrite output file without asking
      '-i', sourcePath, // Input file
      '-c:a', codec, // Audio codec: platform-aware AAC
      '-b:a', '${bitrate}k', // Bitrate
      '-vn', // No video
      '-movflags', '+faststart', // Enable streaming before full download
      '-map_metadata', '-1', // Strip metadata (smaller file, privacy)
      outputPath, // Output file
    ];
  }

  // ==================== Cache Index Methods ====================

  /// Ensure cache index is loaded.
  Future<void> _ensureIndexLoaded() async {
    if (_indexLoaded) return;
    await _loadCacheIndex();
    _indexLoaded = true;
  }

  /// Load cache index from disk.
  Future<void> _loadCacheIndex() async {
    final indexFile = File('$cacheDirectory/cache_index.json');
    if (!await indexFile.exists()) {
      // First run or index lost - rebuild from disk
      await _rebuildCacheIndex();
      return;
    }

    try {
      final content = await indexFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final entries = json['entries'] as Map<String, dynamic>?;
      if (entries != null) {
        _cacheIndex.clear();
        entries.forEach((key, value) {
          _cacheIndex[key] = _CacheIndexEntry.fromJson(value as Map<String, dynamic>);
        });
      }

      _cachedTotalSize = json['totalSize'] as int? ?? 0;
      print('TranscodingService: Loaded cache index (${_cacheIndex.length} entries, '
          '${(_cachedTotalSize / 1024 / 1024).round()} MB)');
    } catch (e) {
      print('TranscodingService: Index corrupt, rebuilding... ($e)');
      await _rebuildCacheIndex();
    }
  }

  /// Rebuild index by scanning disk (fallback).
  Future<void> _rebuildCacheIndex() async {
    _cacheIndex.clear();
    _cachedTotalSize = 0;

    final cacheDir = Directory(cacheDirectory);
    if (!await cacheDir.exists()) {
      print('TranscodingService: Cache directory does not exist, starting fresh');
      return;
    }

    try {
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.m4a')) {
          final stat = await entity.stat();
          final relPath = entity.path.substring(cacheDirectory.length + 1);
          final key = _pathToKey(relPath);

          _cacheIndex[key] = _CacheIndexEntry(
            path: relPath,
            size: stat.size,
            lastAccess: stat.modified,
          );
          _cachedTotalSize += stat.size;
        }
      }

      print('TranscodingService: Rebuilt cache index (${_cacheIndex.length} entries, '
          '${(_cachedTotalSize / 1024 / 1024).round()} MB)');
      await _persistCacheIndex();
    } catch (e) {
      print('TranscodingService: Error rebuilding index - $e');
    }
  }

  /// Convert relative path to cache key.
  String _pathToKey(String relPath) {
    // "medium/songId.m4a" -> "songId_medium"
    final parts = relPath.split('/');
    if (parts.length >= 2) {
      final quality = parts[0];
      final filename = parts[1];
      final songId = filename.replaceAll('.m4a', '');
      return '${songId}_$quality';
    }
    return relPath;
  }

  /// Persist cache index to disk.
  Future<void> _persistCacheIndex() async {
    try {
      final indexFile = File('$cacheDirectory/cache_index.json');
      final tempFile = File('$cacheDirectory/cache_index.json.tmp');

      await indexFile.parent.create(recursive: true);

      final json = jsonEncode({
        'version': 1,
        'entries': _cacheIndex.map((k, v) => MapEntry(k, v.toJson())),
        'totalSize': _cachedTotalSize,
      });

      await tempFile.writeAsString(json);
      await tempFile.rename(indexFile.path);
      _indexDirty = false;
    } catch (e) {
      print('TranscodingService: Error persisting cache index - $e');
    }
  }

  /// Synchronously persist cache index (for dispose).
  void _persistCacheIndexSync() {
    try {
      final indexFile = File('$cacheDirectory/cache_index.json');
      indexFile.parent.createSync(recursive: true);

      final json = jsonEncode({
        'version': 1,
        'entries': _cacheIndex.map((k, v) => MapEntry(k, v.toJson())),
        'totalSize': _cachedTotalSize,
      });

      indexFile.writeAsStringSync(json);
      _indexDirty = false;
    } catch (e) {
      print('TranscodingService: Error persisting cache index sync - $e');
    }
  }

  /// Add entry to cache index.
  void _addToIndex(String key, String path, int size) {
    _cacheIndex[key] = _CacheIndexEntry(
      path: path,
      size: size,
      lastAccess: DateTime.now(),
    );
    _cachedTotalSize += size;
    _indexDirty = true;
  }

  /// Update access time in index (no disk write).
  void _recordAccess(String key) {
    final entry = _cacheIndex[key];
    if (entry != null) {
      entry.lastAccess = DateTime.now();
      _indexDirty = true;
    }
  }

  /// Mark a cache entry as in-use to prevent eviction during streaming.
  ///
  /// Call [releaseInUse] when streaming is complete.
  void markInUse(String songId, QualityPreset quality) {
    final lockKey = '${songId}_${quality.name}';
    _inUse.add(lockKey);
  }

  /// Release a cache entry from in-use status.
  ///
  /// Should be called after streaming completes.
  void releaseInUse(String songId, QualityPreset quality) {
    final lockKey = '${songId}_${quality.name}';
    _inUse.remove(lockKey);
  }

  /// Remove entry from cache index.
  void _removeFromIndex(String key) {
    final entry = _cacheIndex.remove(key);
    if (entry != null) {
      _cachedTotalSize -= entry.size;
      _indexDirty = true;
    }
  }

  // ==================== Failure Backoff Methods ====================

  /// Check if we should skip due to recent failure.
  bool _shouldSkipDueToFailure(String key) {
    final record = _failures[key];
    if (record == null) return false;

    final elapsed = DateTime.now().difference(record.lastFailure);
    if (elapsed > failureBackoffDuration) {
      // Backoff expired, allow retry
      _failures.remove(key);
      return false;
    }

    return true;
  }

  /// Record a failure.
  void _recordFailure(String key, String? errorMessage) {
    final existing = _failures[key];
    _failures[key] = _FailureRecord(
      lastFailure: DateTime.now(),
      failureCount: (existing?.failureCount ?? 0) + 1,
      errorMessage: errorMessage,
    );
    print('TranscodingService: Recorded failure for $key (count: ${_failures[key]!.failureCount})');
  }

  /// Clear failure record (on success).
  void _clearFailure(String key) {
    _failures.remove(key);
  }

  // ==================== Cache Cleanup Methods ====================

  /// Cleanup cache if it exceeds the maximum size.
  ///
  /// Uses LRU (Least Recently Used) eviction strategy based on in-memory index.
  /// Skips entries that are currently in-use to prevent deletion during streaming.
  Future<void> _cleanupCacheIfNeeded() async {
    if (_cachedTotalSize <= maxCacheSizeBytes) return;

    print('TranscodingService: Cache cleanup needed '
        '(${(_cachedTotalSize / 1024 / 1024).round()} MB / '
        '${(maxCacheSizeBytes / 1024 / 1024).round()} MB)');

    // Sort by lastAccess (oldest first) - O(n log n) on index, not disk
    final entries = _cacheIndex.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    int skippedInUse = 0;
    for (final entry in entries) {
      if (_cachedTotalSize <= maxCacheSizeBytes) break;

      // Skip entries that are currently being streamed
      if (_inUse.contains(entry.key)) {
        skippedInUse++;
        continue;
      }

      try {
        final file = File('$cacheDirectory/${entry.value.path}');
        if (await file.exists()) {
          await file.delete();
        }
        _removeFromIndex(entry.key);
        print('TranscodingService: Evicted ${entry.key}');
      } catch (e) {
        print('TranscodingService: Eviction failed for ${entry.key}: $e');
      }
    }

    if (skippedInUse > 0) {
      print('TranscodingService: Skipped $skippedInUse in-use entries during eviction');
    }

    print('TranscodingService: Cache size now '
        '${(_cachedTotalSize / 1024 / 1024).round()} MB');

    // Persist index after cleanup
    await _persistCacheIndex();
  }

  /// Get current cache size in bytes (from index, no disk scan).
  Future<int> getCacheSize() async {
    await _ensureIndexLoaded();
    return _cachedTotalSize;
  }

  /// Clear the entire transcoding cache.
  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      _cacheIndex.clear();
      _cachedTotalSize = 0;
      _indexDirty = false;
      print('TranscodingService: Cache cleared');
    } catch (e) {
      print('TranscodingService: Error clearing cache - $e');
    }
  }

  /// Delete cached transcodes for a specific song.
  ///
  /// Useful when the source file changes.
  Future<void> invalidateSong(String songId) async {
    for (final quality in QualityPreset.values) {
      if (!quality.requiresTranscoding) continue;

      final lockKey = '${songId}_${quality.name}';
      final cachedFile = _getCachedFile(songId, quality);

      if (await cachedFile.exists()) {
        try {
          await cachedFile.delete();
          _removeFromIndex(lockKey);
          print('TranscodingService: Invalidated $songId at ${quality.name}');
        } catch (e) {
          print('TranscodingService: Failed to invalidate $songId: $e');
        }
      } else if (_cacheIndex.containsKey(lockKey)) {
        _removeFromIndex(lockKey);
      }
    }
  }
}

// ==================== Internal Classes ====================

/// Internal class for queued transcode tasks.
class _TranscodeTask {
  final String sourcePath;
  final String songId;
  final QualityPreset quality;
  final Completer<File?> completer;

  _TranscodeTask({
    required this.sourcePath,
    required this.songId,
    required this.quality,
    required this.completer,
  });
}

/// Internal class for cache index entries.
class _CacheIndexEntry {
  final String path;
  final int size;
  DateTime lastAccess;

  _CacheIndexEntry({
    required this.path,
    required this.size,
    required this.lastAccess,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'size': size,
        'lastAccess': lastAccess.toIso8601String(),
      };

  factory _CacheIndexEntry.fromJson(Map<String, dynamic> json) => _CacheIndexEntry(
        path: json['path'] as String,
        size: json['size'] as int,
        lastAccess: DateTime.parse(json['lastAccess'] as String),
      );
}

/// Internal class for failure tracking.
class _FailureRecord {
  final DateTime lastFailure;
  final int failureCount;
  final String? errorMessage;

  _FailureRecord({
    required this.lastFailure,
    required this.failureCount,
    this.errorMessage,
  });
}

/// Internal class for audio file properties.
class _AudioProperties {
  final String? codec;
  final int? bitrate; // bits per second
  final int? sampleRate;

  _AudioProperties({
    this.codec,
    this.bitrate,
    this.sampleRate,
  });

  /// Returns true if source bitrate is at or below target.
  bool shouldSkipTranscode(QualityPreset quality) {
    if (bitrate == null) return false;
    final targetBps = (quality.bitrate ?? 0) * 1000; // kbps to bps
    return bitrate! <= targetBps;
  }
}

/// Result of a streaming transcode operation.
class StreamTranscodeResult {
  /// The stream of audio bytes to send to the client.
  final Stream<List<int>> stream;

  /// Future that completes when the cache file is ready (or null on failure).
  final Future<File?> cacheFile;

  /// MIME type for the transcoded audio.
  final String mimeType;

  StreamTranscodeResult({
    required this.stream,
    required this.cacheFile,
    required this.mimeType,
  });
}

/// Result of a download transcode operation.
///
/// Contains a temporary file that should be deleted by the caller
/// after the download completes.
class DownloadTranscodeResult {
  /// The temporary transcoded file.
  final File tempFile;

  /// Whether the caller should delete this file after use.
  final bool shouldDelete;

  DownloadTranscodeResult({
    required this.tempFile,
    required this.shouldDelete,
  });

  /// Delete the temporary file. Call this after download completes.
  Future<void> cleanup() async {
    if (shouldDelete) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }
}
