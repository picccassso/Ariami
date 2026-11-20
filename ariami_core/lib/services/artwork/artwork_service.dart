import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/artwork_size.dart';
import 'ffmpeg_probe.dart';

export 'ffmpeg_probe.dart' show ArtworkProcessRunner;

enum ArtworkFormat {
  jpeg('image/jpeg', 'jpg'),
  webp('image/webp', 'webp');

  const ArtworkFormat(this.contentType, this.extension);

  final String contentType;
  final String extension;
}

/// Service for processing and caching album artwork at different sizes.
///
/// Uses FFmpeg for image resizing and maintains a cache of processed images
/// to avoid re-processing on subsequent requests.
class ArtworkService {
  final String cacheDirectory;

  /// Maximum cache size in bytes (default 256MB)
  final int maxCacheSizeBytes;

  /// Whether cache hits should update file mtimes for LRU tracking.
  final bool touchOnCacheHit;

  /// Minimum age before a cache hit updates mtime again.
  final Duration touchThrottle;

  /// Maximum concurrent FFmpeg artwork resize processes.
  final int maxConcurrency;

  final ArtworkProcessRunner _processRunner;
  late final FfmpegProbe _ffmpeg = FfmpegProbe(_processRunner);

  /// Lock to prevent concurrent processing of the same artwork
  final Map<String, Completer<Uint8List?>> _processingLocks = {};
  final Queue<Completer<void>> _slotWaiters = Queue();
  int _activeProcesses = 0;

  int _cachedTotalSize = 0;
  bool _cacheSizeLoaded = false;
  bool _cleanupInFlight = false;

  ArtworkService({
    required this.cacheDirectory,
    int maxCacheSizeMB = 256,
    this.touchOnCacheHit = true,
    this.touchThrottle = Duration.zero,
    this.maxConcurrency = 4,
    ArtworkProcessRunner? processRunner,
  })  : maxCacheSizeBytes = maxCacheSizeMB * 1024 * 1024,
        _processRunner = processRunner ??
            ((executable, arguments) => Process.run(executable, arguments));

  Future<bool> isFFmpegAvailable() => _ffmpeg.isAvailable();

  Future<bool> isWebpAvailable() => _ffmpeg.isWebpAvailable();

  /// Fast-path disk cache lookup using [sourceStamp] (path/mtime/size) without
  /// extracting or hashing the full-size original artwork.
  Future<Uint8List?> getCachedArtwork(
    String albumId,
    ArtworkSize size, {
    required String sourceStamp,
    ArtworkFormat format = ArtworkFormat.jpeg,
  }) async {
    if (!size.requiresProcessing || sourceStamp.isEmpty) return null;
    final cachedFile = _getCachedFile(albumId, size, format: format);
    if (!await cachedFile.exists()) return null;
    try {
      final stampFile = _getSourceStampFile(cachedFile);
      if (!await stampFile.exists()) return null;
      final cachedStamp = (await stampFile.readAsString()).trim();
      if (cachedStamp != sourceStamp) return null;
      await _touchFile(cachedFile);
      final bytes = await cachedFile.readAsBytes();
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> getArtwork(
    String albumId,
    List<int> originalArtwork,
    ArtworkSize size, {
    ArtworkFormat format = ArtworkFormat.jpeg,
    String? sourceStamp,
  }) async {
    final originalBytes = originalArtwork is Uint8List
        ? originalArtwork
        : Uint8List.fromList(originalArtwork);

    if (!size.requiresProcessing) {
      return originalBytes;
    }

    final effectiveFormat = format == ArtworkFormat.webp &&
            await isWebpAvailable()
        ? ArtworkFormat.webp
        : ArtworkFormat.jpeg;

    final cachedFile = _getCachedFile(albumId, size, format: effectiveFormat);
    if (await cachedFile.exists()) {
      try {
        final sourceDigest = _sourceDigest(originalBytes);
        final digestFile = _getSourceDigestFile(cachedFile);
        final cachedDigest = await digestFile.exists()
            ? (await digestFile.readAsString()).trim()
            : null;
        if (cachedDigest == sourceDigest) {
          if (sourceStamp != null && sourceStamp.isNotEmpty) {
            final stampFile = _getSourceStampFile(cachedFile);
            if (!await stampFile.exists()) {
              await stampFile.writeAsString(sourceStamp);
            }
          }
          await _touchFile(cachedFile);
          return await cachedFile.readAsBytes();
        }

        await cachedFile.delete();
        if (await digestFile.exists()) await digestFile.delete();
        final stampFile = _getSourceStampFile(cachedFile);
        if (await stampFile.exists()) await stampFile.delete();
      } catch (e) {
        print('[ArtworkService] Error reading cached file: $e');
      }
    }

    if (!await isFFmpegAvailable()) {
      return originalBytes;
    }

    final lockKey = '${albumId}_${size.name}_${effectiveFormat.extension}';
    if (_processingLocks.containsKey(lockKey)) {
      final result = await _processingLocks[lockKey]!.future;
      return result ?? originalBytes;
    }

    final completer = Completer<Uint8List?>();
    _processingLocks[lockKey] = completer;

    try {
      final result = await _processArtwork(
        albumId,
        originalBytes,
        size,
        format: effectiveFormat,
        sourceStamp: sourceStamp,
      );

      if (result != null) {
        if (_cacheSizeLoaded) {
          _cachedTotalSize += result.length;
        }
        if (!_cacheSizeLoaded || _cachedTotalSize > maxCacheSizeBytes) {
          unawaited(_cleanupCacheIfNeeded());
        }
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

  /// Precompute a variant during indexing.
  ///
  /// Uses the same processing/caching path as request-time artwork serving.
  Future<Uint8List> precomputeArtworkVariant(
    String artworkKey,
    List<int> originalArtwork,
    ArtworkSize size, {
    ArtworkFormat format = ArtworkFormat.jpeg,
    String? sourceStamp,
  }) async {
    return getArtwork(
      artworkKey,
      originalArtwork,
      size,
      format: format,
      sourceStamp: sourceStamp,
    );
  }

  /// Returns the expected storage path for a variant.
  ///
  /// For `full`, this returns [originalReferencePath].
  /// For processed variants, this returns the cache file path.
  String getVariantStoragePath(
    String artworkKey,
    ArtworkSize size, {
    String? originalReferencePath,
    ArtworkFormat format = ArtworkFormat.jpeg,
  }) {
    if (!size.requiresProcessing) {
      return originalReferencePath ?? '';
    }
    return _getCachedFile(artworkKey, size, format: format).path;
  }

  File _getCachedFile(
    String albumId,
    ArtworkSize size, {
    ArtworkFormat format = ArtworkFormat.jpeg,
  }) {
    final safeId = albumId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final dirPath = format == ArtworkFormat.webp
        ? '$cacheDirectory/${size.name}/webp'
        : '$cacheDirectory/${size.name}';
    return File('$dirPath/$safeId.${format.extension}');
  }

  File _getSourceDigestFile(File cachedFile) {
    return File('${cachedFile.path}.source-md5');
  }

  File _getSourceStampFile(File cachedFile) {
    return File('${cachedFile.path}.source-stamp');
  }

  String _sourceDigest(List<int> bytes) => md5.convert(bytes).toString();

  Future<void> _touchFile(File file) async {
    if (!touchOnCacheHit) return;

    try {
      if (touchThrottle > Duration.zero) {
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified);
        if (age < touchThrottle) return;
      }
      await file.setLastModified(DateTime.now());
    } catch (e) {
      // Ignore errors - not critical
    }
  }

  Future<void> _acquireSlot() async {
    if (_activeProcesses < maxConcurrency) {
      _activeProcesses++;
      return;
    }
    final waiter = Completer<void>();
    _slotWaiters.add(waiter);
    await waiter.future;
  }

  void _releaseSlot() {
    if (_slotWaiters.isNotEmpty) {
      _slotWaiters.removeFirst().complete();
    } else if (_activeProcesses > 0) {
      _activeProcesses--;
    }
  }

  Future<Uint8List?> _processArtwork(
    String albumId,
    Uint8List originalArtwork,
    ArtworkSize size, {
    ArtworkFormat format = ArtworkFormat.jpeg,
    String? sourceStamp,
  }) async {
    await _acquireSlot();
    final outputFile = _getCachedFile(albumId, size, format: format);
    final outputDir = outputFile.parent;
    final safeId = albumId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final tempInput = File(
      '${Directory.systemTemp.path}/ariami_artwork_in_${safeId}_${size.name}_${format.extension}',
    );
    final tempOutput = File(
      '${outputFile.path}.tmp.${format.extension}',
    );

    try {
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      await tempInput.writeAsBytes(originalArtwork);

      final maxDim = size.maxDimension!;
      final scaleFilter =
          'scale=$maxDim:$maxDim:force_original_aspect_ratio=decrease';
      final args = format == ArtworkFormat.webp
          ? [
              '-y',
              '-i',
              tempInput.path,
              '-vf',
              scaleFilter,
              '-c:v',
              'libwebp',
              '-quality',
              size == ArtworkSize.thumbnail ? '78' : '82',
              '-compression_level',
              '4',
              tempOutput.path,
            ]
          : [
              '-y',
              '-i',
              tempInput.path,
              '-vf',
              scaleFilter,
              '-q:v',
              size == ArtworkSize.thumbnail ? '5' : '3',
              tempOutput.path,
            ];

      final result = await _processRunner('ffmpeg', args).timeout(
        const Duration(seconds: 10),
        onTimeout: () => ProcessResult(-1, -1, '', 'Timeout'),
      );

      if (result.exitCode == 0 && await tempOutput.exists()) {
        final thumbnailBytes = await tempOutput.readAsBytes();
        await tempOutput.rename(outputFile.path);
        await _getSourceDigestFile(outputFile).writeAsString(
          _sourceDigest(originalArtwork),
        );
        if (sourceStamp != null && sourceStamp.isNotEmpty) {
          await _getSourceStampFile(outputFile).writeAsString(sourceStamp);
        }
        return thumbnailBytes;
      }

      return null;
    } catch (e) {
      print('[ArtworkService] Processing error - $e');
      return null;
    } finally {
      _releaseSlot();
      try {
        if (await tempInput.exists()) await tempInput.delete();
      } catch (_) {}
      try {
        if (await tempOutput.exists()) await tempOutput.delete();
      } catch (_) {}
    }
  }

  Future<void> _cleanupCacheIfNeeded() async {
    if (_cleanupInFlight) return;
    _cleanupInFlight = true;
    try {
      final cacheDir = Directory(cacheDirectory);
      if (!await cacheDir.exists()) {
        _cachedTotalSize = 0;
        _cacheSizeLoaded = true;
        return;
      }

      final files = <_CachedArtworkInfo>[];

      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File &&
            (entity.path.endsWith('.jpg') || entity.path.endsWith('.webp'))) {
          final stat = await entity.stat();
          files.add(_CachedArtworkInfo(
            file: entity,
            size: stat.size,
            lastAccessed: stat.modified,
          ));
        }
      }

      int totalSize = files.fold(0, (sum, f) => sum + f.size);
      _cachedTotalSize = totalSize;
      _cacheSizeLoaded = true;
      if (totalSize <= maxCacheSizeBytes) return;

      files.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

      for (final fileInfo in files) {
        if (totalSize <= maxCacheSizeBytes) break;

        try {
          await fileInfo.file.delete();
          final digestFile = _getSourceDigestFile(fileInfo.file);
          if (await digestFile.exists()) await digestFile.delete();
          final stampFile = _getSourceStampFile(fileInfo.file);
          if (await stampFile.exists()) await stampFile.delete();
          totalSize -= fileInfo.size;
        } catch (_) {}
      }
      _cachedTotalSize = totalSize;
    } catch (e) {
      print('[ArtworkService] Cache cleanup error - $e');
    } finally {
      _cleanupInFlight = false;
    }
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(cacheDirectory);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        print('[ArtworkService] Cache cleared');
      }
      _cachedTotalSize = 0;
      _cacheSizeLoaded = true;
    } catch (e) {
      print('[ArtworkService] Error clearing cache - $e');
    }
  }
}

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
