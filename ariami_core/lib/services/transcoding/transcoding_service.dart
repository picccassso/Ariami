import 'dart:async';
import 'dart:io';

import '../../models/quality_preset.dart';

/// Service for transcoding audio files to different quality levels.
///
/// Uses FFmpeg for transcoding and maintains a cache of transcoded files
/// to avoid re-transcoding on subsequent requests.
class TranscodingService {
  /// Base directory for transcoded file cache
  final String cacheDirectory;

  /// Maximum cache size in bytes (default 2GB)
  final int maxCacheSizeBytes;

  /// Whether FFmpeg is available on this system
  bool? _ffmpegAvailable;

  /// Lock to prevent concurrent transcoding of the same file
  final Map<String, Completer<File?>> _transcodingLocks = {};

  /// Creates a new TranscodingService.
  ///
  /// [cacheDirectory] - Base directory for storing transcoded files.
  /// [maxCacheSizeMB] - Maximum cache size in megabytes (default 2048 = 2GB).
  TranscodingService({
    required this.cacheDirectory,
    int maxCacheSizeMB = 2048,
  }) : maxCacheSizeBytes = maxCacheSizeMB * 1024 * 1024;

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

  /// Get a transcoded file for the given source and quality.
  ///
  /// Returns the transcoded file if it exists in cache or after transcoding.
  /// Returns null if:
  /// - Quality is [QualityPreset.high] (no transcoding needed)
  /// - FFmpeg is not available
  /// - Transcoding fails
  ///
  /// [sourcePath] - Path to the original audio file.
  /// [songId] - Unique identifier for the song (used for cache filename).
  /// [quality] - Target quality preset.
  Future<File?> getTranscodedFile(
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
      print('TranscodingService: Cannot transcode - FFmpeg not available');
      return null;
    }

    // Check cache first
    final cachedFile = _getCachedFile(songId, quality);
    if (await cachedFile.exists()) {
      print('TranscodingService: Cache hit for $songId at ${quality.name}');
      // Update access time for LRU tracking
      await _touchFile(cachedFile);
      return cachedFile;
    }

    // Check if already transcoding
    final lockKey = '${songId}_${quality.name}';
    if (_transcodingLocks.containsKey(lockKey)) {
      print('TranscodingService: Waiting for existing transcode of $songId');
      return await _transcodingLocks[lockKey]!.future;
    }

    // Start transcoding with lock
    final completer = Completer<File?>();
    _transcodingLocks[lockKey] = completer;

    try {
      print('TranscodingService: Transcoding $songId to ${quality.name}');
      final result = await _transcodeFile(sourcePath, cachedFile.path, quality);

      if (result != null) {
        // Cleanup cache if needed (async, don't wait)
        _cleanupCacheIfNeeded();
      }

      completer.complete(result);
      return result;
    } catch (e) {
      print('TranscodingService: Transcode error - $e');
      completer.complete(null);
      return null;
    } finally {
      _transcodingLocks.remove(lockKey);
    }
  }

  /// Get the cached file path for a song at a specific quality.
  File _getCachedFile(String songId, QualityPreset quality) {
    final qualityDir = Directory('$cacheDirectory/${quality.name}');
    return File('${qualityDir.path}/$songId.${quality.fileExtension}');
  }

  /// Update file access time for LRU tracking.
  Future<void> _touchFile(File file) async {
    try {
      // Read and rewrite the file's last modified time
      await file.setLastModified(DateTime.now());
    } catch (e) {
      // Ignore errors - not critical
    }
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

    // Build FFmpeg command
    final args = _buildFFmpegArgs(sourcePath, outputPath, quality);

    print('TranscodingService: Running ffmpeg ${args.join(' ')}');

    try {
      final result = await Process.run(
        'ffmpeg',
        args,
        // Timeout after 5 minutes for very large files
      ).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          print('TranscodingService: Transcode timeout');
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
  List<String> _buildFFmpegArgs(
    String sourcePath,
    String outputPath,
    QualityPreset quality,
  ) {
    final bitrate = quality.bitrate;
    if (bitrate == null) {
      throw ArgumentError('Cannot build FFmpeg args for high quality');
    }

    return [
      '-y', // Overwrite output file without asking
      '-i', sourcePath, // Input file
      '-c:a', 'aac', // Audio codec: AAC
      '-b:a', '${bitrate}k', // Bitrate
      '-vn', // No video
      '-movflags', '+faststart', // Enable streaming before full download
      '-map_metadata', '-1', // Strip metadata (smaller file, privacy)
      outputPath, // Output file
    ];
  }

  /// Cleanup cache if it exceeds the maximum size.
  ///
  /// Uses LRU (Least Recently Used) eviction strategy.
  Future<void> _cleanupCacheIfNeeded() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (!await cacheDir.exists()) return;

      // Collect all cached files with their stats
      final files = <_CachedFileInfo>[];

      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.m4a')) {
          final stat = await entity.stat();
          files.add(_CachedFileInfo(
            file: entity,
            size: stat.size,
            lastAccessed: stat.modified, // Using modified as proxy for accessed
          ));
        }
      }

      // Calculate total size
      int totalSize = files.fold(0, (sum, f) => sum + f.size);

      if (totalSize <= maxCacheSizeBytes) {
        return; // Under limit, no cleanup needed
      }

      print('TranscodingService: Cache cleanup needed '
          '(${(totalSize / 1024 / 1024).round()} MB / '
          '${(maxCacheSizeBytes / 1024 / 1024).round()} MB)');

      // Sort by last accessed (oldest first)
      files.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

      // Delete oldest files until under limit
      for (final fileInfo in files) {
        if (totalSize <= maxCacheSizeBytes) break;

        try {
          await fileInfo.file.delete();
          totalSize -= fileInfo.size;
          print('TranscodingService: Evicted ${fileInfo.file.path}');
        } catch (e) {
          print('TranscodingService: Failed to delete ${fileInfo.file.path}: $e');
        }
      }

      print('TranscodingService: Cache size now '
          '${(totalSize / 1024 / 1024).round()} MB');
    } catch (e) {
      print('TranscodingService: Cache cleanup error - $e');
    }
  }

  /// Get current cache size in bytes.
  Future<int> getCacheSize() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (!await cacheDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      print('TranscodingService: Error getting cache size - $e');
      return 0;
    }
  }

  /// Clear the entire transcoding cache.
  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        print('TranscodingService: Cache cleared');
      }
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

      final cachedFile = _getCachedFile(songId, quality);
      if (await cachedFile.exists()) {
        try {
          await cachedFile.delete();
          print('TranscodingService: Invalidated $songId at ${quality.name}');
        } catch (e) {
          print('TranscodingService: Failed to invalidate $songId: $e');
        }
      }
    }
  }
}

/// Internal class for tracking cached file info during cleanup.
class _CachedFileInfo {
  final File file;
  final int size;
  final DateTime lastAccessed;

  _CachedFileInfo({
    required this.file,
    required this.size,
    required this.lastAccessed,
  });
}
