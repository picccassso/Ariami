part of 'package:ariami_core/services/transcoding/transcoding_service.dart';

extension _TranscodingServiceCache on TranscodingService {
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
          _cacheIndex[key] =
              _CacheIndexEntry.fromJson(value as Map<String, dynamic>);
        });
      }

      _cachedTotalSize = json['totalSize'] as int? ?? 0;
      print(
          'TranscodingService: Loaded cache index (${_cacheIndex.length} entries, '
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
      print(
          'TranscodingService: Cache directory does not exist, starting fresh');
      return;
    }

    try {
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File &&
            (entity.path.endsWith('.aac') || entity.path.endsWith('.m4a'))) {
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

      print(
          'TranscodingService: Rebuilt cache index (${_cacheIndex.length} entries, '
          '${(_cachedTotalSize / 1024 / 1024).round()} MB)');
      await _persistCacheIndex();
    } catch (e) {
      print('TranscodingService: Error rebuilding index - $e');
    }
  }

  /// Convert relative path to cache key.
  String _pathToKey(String relPath) {
    // "medium/songId.aac" -> "songId_medium"
    final parts = relPath.split('/');
    if (parts.length >= 2) {
      final quality = parts[0];
      final filename = parts[1];
      final songId = filename.replaceFirst(RegExp(r'\.(aac|m4a)$'), '');
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
  void _markInUse(String songId, QualityPreset quality) {
    final lockKey = '${songId}_${quality.name}';
    _inUse.add(lockKey);
  }

  /// Release a cache entry from in-use status.
  ///
  /// Should be called after streaming completes.
  void _releaseInUse(String songId, QualityPreset quality) {
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
    print(
        'TranscodingService: Recorded failure for $key (count: ${_failures[key]!.failureCount})');
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
      print(
          'TranscodingService: Skipped $skippedInUse in-use entries during eviction');
    }

    print('TranscodingService: Cache size now '
        '${(_cachedTotalSize / 1024 / 1024).round()} MB');

    // Persist index after cleanup
    await _persistCacheIndex();
  }

  /// Get current cache size in bytes (from index, no disk scan).
  Future<int> _getCacheSize() async {
    await _ensureIndexLoaded();
    return _cachedTotalSize;
  }

  /// Clear the entire transcoding cache.
  Future<void> _clearCache() async {
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
  Future<void> _invalidateSong(String songId) async {
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
