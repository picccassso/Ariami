import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../models/artwork_size.dart';

/// Service for processing and caching album artwork at different sizes.
///
/// Uses FFmpeg for image resizing and maintains a cache of processed images
/// to avoid re-processing on subsequent requests.
class ArtworkService {
  /// Base directory for artwork cache
  final String cacheDirectory;

  /// Maximum cache size in bytes (default 256MB)
  final int maxCacheSizeBytes;

  /// Whether FFmpeg is available on this system
  bool? _ffmpegAvailable;

  /// Lock to prevent concurrent processing of the same artwork
  final Map<String, Completer<Uint8List?>> _processingLocks = {};

  /// Creates a new ArtworkService.
  ///
  /// [cacheDirectory] - Base directory for storing processed artwork.
  /// [maxCacheSizeMB] - Maximum cache size in megabytes (default 256).
  ArtworkService({
    required this.cacheDirectory,
    int maxCacheSizeMB = 256,
  }) : maxCacheSizeBytes = maxCacheSizeMB * 1024 * 1024;

  /// Check if FFmpeg is available on the system.
  Future<bool> isFFmpegAvailable() async {
    if (_ffmpegAvailable != null) return _ffmpegAvailable!;

    try {
      final result = await Process.run('ffmpeg', ['-version']);
      _ffmpegAvailable = result.exitCode == 0;
      if (_ffmpegAvailable!) {
        print('[ArtworkService] FFmpeg is available');
      } else {
        print('[ArtworkService] FFmpeg not found (exit code ${result.exitCode})');
      }
    } catch (e) {
      print('[ArtworkService] FFmpeg not available - $e');
      _ffmpegAvailable = false;
    }

    return _ffmpegAvailable!;
  }

  /// Get artwork at the specified size.
  ///
  /// Returns the processed artwork bytes, or the original if:
  /// - Size is [ArtworkSize.full] (no processing needed)
  /// - FFmpeg is not available
  /// - Processing fails
  ///
  /// [albumId] - Unique identifier for the album (used for cache filename).
  /// [originalArtwork] - Original artwork bytes.
  /// [size] - Target size preset.
  Future<Uint8List> getArtwork(
    String albumId,
    List<int> originalArtwork,
    ArtworkSize size,
  ) async {
    final originalBytes = originalArtwork is Uint8List
        ? originalArtwork
        : Uint8List.fromList(originalArtwork);

    // No processing needed for full size
    if (!size.requiresProcessing) {
      return originalBytes;
    }

    // Check FFmpeg availability
    if (!await isFFmpegAvailable()) {
      print('[ArtworkService] Cannot resize - FFmpeg not available, returning original');
      return originalBytes;
    }

    // Check cache first
    final cachedFile = _getCachedFile(albumId, size);
    if (await cachedFile.exists()) {
      try {
        print('[ArtworkService] Cache hit for $albumId at ${size.name}');
        await _touchFile(cachedFile);
        return await cachedFile.readAsBytes();
      } catch (e) {
        print('[ArtworkService] Error reading cached file: $e');
        // Fall through to regenerate
      }
    }

    // Check if already processing
    final lockKey = '${albumId}_${size.name}';
    if (_processingLocks.containsKey(lockKey)) {
      print('[ArtworkService] Waiting for existing processing of $albumId');
      final result = await _processingLocks[lockKey]!.future;
      return result ?? originalBytes;
    }

    // Start processing with lock
    final completer = Completer<Uint8List?>();
    _processingLocks[lockKey] = completer;

    try {
      print('[ArtworkService] Processing $albumId to ${size.name} (${size.maxDimension}x${size.maxDimension})');
      final result = await _processArtwork(albumId, originalBytes, size);

      if (result != null) {
        // Cleanup cache if needed (async, don't wait)
        _cleanupCacheIfNeeded();
        completer.complete(result);
        return result;
      }

      completer.complete(null);
      return originalBytes;
    } catch (e) {
      print('[ArtworkService] Processing error - $e');
      completer.complete(null);
      return originalBytes;
    } finally {
      _processingLocks.remove(lockKey);
    }
  }

  /// Get the cached file path for artwork at a specific size.
  File _getCachedFile(String albumId, ArtworkSize size) {
    // Sanitize albumId for use in filename
    final safeId = albumId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final sizeDir = Directory('$cacheDirectory/${size.name}');
    return File('${sizeDir.path}/$safeId.jpg');
  }

  /// Update file access time for LRU tracking.
  Future<void> _touchFile(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } catch (e) {
      // Ignore errors - not critical
    }
  }

  /// Process artwork using FFmpeg to resize to target size.
  Future<Uint8List?> _processArtwork(
    String albumId,
    Uint8List originalArtwork,
    ArtworkSize size,
  ) async {
    // Ensure output directory exists
    final outputFile = _getCachedFile(albumId, size);
    final outputDir = outputFile.parent;
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Write original to temp file
    final tempDir = Directory.systemTemp;
    final tempInput = File('${tempDir.path}/ariami_artwork_input_$albumId');
    final tempOutput = File('${tempDir.path}/ariami_artwork_output_$albumId.jpg');

    try {
      // Write input
      await tempInput.writeAsBytes(originalArtwork);

      // Build FFmpeg command for resizing
      final maxDim = size.maxDimension!;
      final args = [
        '-y', // Overwrite output
        '-i', tempInput.path, // Input file
        '-vf', 'scale=$maxDim:$maxDim:force_original_aspect_ratio=decrease', // Scale preserving aspect ratio
        '-q:v', '3', // JPEG quality (2-5 is good, lower = better quality)
        tempOutput.path, // Output file
      ];

      print('[ArtworkService] Running: ffmpeg ${args.join(' ')}');

      final result = await Process.run('ffmpeg', args).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('[ArtworkService] Resize timeout');
          return ProcessResult(-1, -1, '', 'Timeout');
        },
      );

      if (result.exitCode == 0 && await tempOutput.exists()) {
        final thumbnailBytes = await tempOutput.readAsBytes();
        final originalSize = originalArtwork.length;
        final newSize = thumbnailBytes.length;

        print('[ArtworkService] Resize complete: '
            '${(originalSize / 1024).round()} KB -> ${(newSize / 1024).round()} KB '
            '(${((1 - newSize / originalSize) * 100).round()}% reduction)');

        // Save to cache
        await outputFile.writeAsBytes(thumbnailBytes);

        return thumbnailBytes;
      }

      print('[ArtworkService] FFmpeg failed (exit ${result.exitCode})');
      if (result.stderr.toString().isNotEmpty) {
        print('[ArtworkService] stderr: ${result.stderr}');
      }

      return null;
    } catch (e) {
      print('[ArtworkService] Processing error - $e');
      return null;
    } finally {
      // Cleanup temp files
      try {
        if (await tempInput.exists()) await tempInput.delete();
      } catch (_) {}
      try {
        if (await tempOutput.exists()) await tempOutput.delete();
      } catch (_) {}
    }
  }

  /// Cleanup cache if it exceeds the maximum size.
  ///
  /// Uses LRU (Least Recently Used) eviction strategy.
  Future<void> _cleanupCacheIfNeeded() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (!await cacheDir.exists()) return;

      // Collect all cached files with their stats
      final files = <_CachedArtworkInfo>[];

      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final stat = await entity.stat();
          files.add(_CachedArtworkInfo(
            file: entity,
            size: stat.size,
            lastAccessed: stat.modified,
          ));
        }
      }

      // Calculate total size
      int totalSize = files.fold(0, (sum, f) => sum + f.size);

      if (totalSize <= maxCacheSizeBytes) {
        return; // Under limit, no cleanup needed
      }

      print('[ArtworkService] Cache cleanup needed '
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
          print('[ArtworkService] Evicted ${fileInfo.file.path}');
        } catch (e) {
          print('[ArtworkService] Failed to delete ${fileInfo.file.path}: $e');
        }
      }

      print('[ArtworkService] Cache size now '
          '${(totalSize / 1024 / 1024).round()} MB');
    } catch (e) {
      print('[ArtworkService] Cache cleanup error - $e');
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
      print('[ArtworkService] Error getting cache size - $e');
      return 0;
    }
  }

  /// Clear the entire artwork cache.
  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        print('[ArtworkService] Cache cleared');
      }
    } catch (e) {
      print('[ArtworkService] Error clearing cache - $e');
    }
  }

  /// Delete cached artwork for a specific album.
  ///
  /// Useful when the source artwork changes.
  Future<void> invalidateAlbum(String albumId) async {
    for (final size in ArtworkSize.values) {
      if (!size.requiresProcessing) continue;

      final cachedFile = _getCachedFile(albumId, size);
      if (await cachedFile.exists()) {
        try {
          await cachedFile.delete();
          print('[ArtworkService] Invalidated $albumId at ${size.name}');
        } catch (e) {
          print('[ArtworkService] Failed to invalidate $albumId: $e');
        }
      }
    }
  }
}

/// Internal class for tracking cached file info during cleanup.
class _CachedArtworkInfo {
  final File file;
  final int size;
  final DateTime lastAccessed;

  _CachedArtworkInfo({
    required this.file,
    required this.size,
    required this.lastAccessed,
  });
}
