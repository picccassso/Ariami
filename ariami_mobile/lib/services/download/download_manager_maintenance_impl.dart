part of 'download_manager.dart';

extension _DownloadManagerMaintenanceImpl on DownloadManager {
  /// Cache artwork for a downloaded song (for offline use) by reading embedded
  /// art from the local audio file — no extra HTTP requests to the server.
  Future<void> _cacheArtworkForDownload(DownloadTask task) async {
    final cacheManager = CacheManager();
    final localPath = _getSongFilePath(task.songId);
    final file = File(localPath);
    if (!await file.exists()) return;

    try {
      final bytes = await LocalArtworkExtractor.extractArtwork(localPath);
      if (bytes == null || bytes.isEmpty) {
        print('[DownloadManager] No embedded artwork for song ${task.songId}');
        return;
      }

      final songKey = 'song_${task.songId}';
      if (!await cacheManager.isArtworkCached(songKey)) {
        await cacheManager.cacheArtworkFromBytes(songKey, bytes);
      }

      if (task.albumId != null &&
          !await cacheManager.isArtworkCached(task.albumId!)) {
        await cacheManager.cacheArtworkFromBytes(task.albumId!, bytes);
      }
      if (task.albumId != null) {
        final thumbKey = '${task.albumId!}_thumb';
        if (!await cacheManager.isArtworkCached(thumbKey)) {
          await cacheManager.cacheArtworkFromBytes(thumbKey, bytes);
        }
      }
    } catch (e) {
      // Don't fail the download if artwork caching fails
      print('[DownloadManager] Failed to cache artwork: $e');
    }
  }

  /// One-time backfill: extract embedded art from already-downloaded files
  /// (works offline; no server required).
  Future<void> _backfillArtworkForExistingDownloads() async {
    const backfillKey = 'artwork_backfill_v4';
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(backfillKey) == true) {
      return;
    }

    final completedTasks = _queue.queue
        .where((task) => task.status == DownloadStatus.completed)
        .toList();

    if (completedTasks.isEmpty) {
      await prefs.setBool(backfillKey, true);
      return;
    }

    print(
        '[DownloadManager] Starting local artwork backfill for ${completedTasks.length} downloaded songs...');

    final cacheManager = CacheManager();
    var backfilledCount = 0;

    for (final task in completedTasks) {
      try {
        final localPath = _getSongFilePath(task.songId);
        final file = File(localPath);
        if (!await file.exists()) continue;

        final bytes = await LocalArtworkExtractor.extractArtwork(localPath);
        if (bytes == null || bytes.isEmpty) continue;

        final songKey = 'song_${task.songId}';
        if (!await cacheManager.isArtworkCached(songKey)) {
          await cacheManager.cacheArtworkFromBytes(songKey, bytes);
        }
        if (task.albumId != null &&
            !await cacheManager.isArtworkCached(task.albumId!)) {
          await cacheManager.cacheArtworkFromBytes(task.albumId!, bytes);
        }
        if (task.albumId != null) {
          final thumbKey = '${task.albumId!}_thumb';
          if (!await cacheManager.isArtworkCached(thumbKey)) {
            await cacheManager.cacheArtworkFromBytes(thumbKey, bytes);
          }
        }
        backfilledCount++;
      } catch (e) {
        print('[DownloadManager] Backfill failed for ${task.songId}: $e');
      }
    }

    await prefs.setBool(backfillKey, true);
    print(
        '[DownloadManager] Local artwork backfill complete: $backfilledCount songs processed');
  }

  /// Get file path for a downloaded song
  String _getSongFilePath(String songId) {
    final downloadPath = _downloadPath;
    if (downloadPath == null || downloadPath.isEmpty) {
      return 'downloads/songs/$songId.mp3';
    }
    return '$downloadPath/songs/$songId.mp3';
  }

  Future<bool> _deleteSongFileIfUnreferenced(String songId) async {
    final normalizedSongId = songId.trim();
    if (normalizedSongId.isEmpty) {
      return false;
    }
    if (_queue.queue.any((task) => task.songId == normalizedSongId)) {
      return false;
    }

    final songFile = File(_getSongFilePath(normalizedSongId));
    if (!await songFile.exists()) {
      return false;
    }

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await songFile.delete();
        return true;
      } catch (e) {
        if (attempt == 3) {
          print(
              '[DownloadManager] Failed to delete local file for song $normalizedSongId: $e');
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return false;
  }

  Future<int> _clearAllDownloadFilesFromDisk() async {
    final downloadPath = _downloadPath;
    if (downloadPath == null || downloadPath.isEmpty) {
      return 0;
    }

    final downloadsDir = Directory(downloadPath);
    if (!await downloadsDir.exists()) {
      return 0;
    }

    var fileCount = 0;
    await for (final entity in downloadsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        fileCount++;
      }
    }

    try {
      await downloadsDir.delete(recursive: true);
    } catch (e) {
      print('[DownloadManager] Failed to clear downloads directory: $e');
      if (await downloadsDir.exists()) {
        await for (final entity in downloadsDir.list(
          recursive: true,
          followLinks: false,
        )) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    }

    await Directory(downloadPath).create(recursive: true);
    await Directory('$downloadPath/songs').create(recursive: true);
    return fileCount;
  }

  Future<int> _cleanupStaleDownloadFiles() async {
    final downloadPath = _downloadPath;
    if (downloadPath == null || downloadPath.isEmpty) {
      return 0;
    }

    final songsDir = Directory('$downloadPath/songs');
    if (!await songsDir.exists()) {
      return 0;
    }

    final knownSongIds = _queue.queue.map((task) => task.songId.trim()).toSet();
    var removedCount = 0;

    await for (final entity in songsDir.list(followLinks: false)) {
      if (entity is Directory) {
        try {
          await entity.delete(recursive: true);
          removedCount++;
        } catch (e) {
          print(
              '[DownloadManager] Failed to remove stale download directory ${entity.path}: $e');
        }
        continue;
      }
      if (entity is! File) {
        continue;
      }

      final fileName = entity.path.split(Platform.pathSeparator).last;
      final songId = _songIdFromDownloadFileName(fileName);
      final isKnownSongFile = songId != null && knownSongIds.contains(songId);
      if (isKnownSongFile) {
        continue;
      }

      try {
        await entity.delete();
        removedCount++;
      } catch (e) {
        print(
            '[DownloadManager] Failed to remove stale download file ${entity.path}: $e');
      }
    }

    if (removedCount > 0) {
      print(
          '[DownloadManager] Removed $removedCount stale local download file(s)');
    }
    return removedCount;
  }

  String? _songIdFromDownloadFileName(String fileName) {
    if (fileName.length <= 4 || !fileName.toLowerCase().endsWith('.mp3')) {
      return null;
    }
    return fileName.substring(0, fileName.length - 4).trim();
  }

  /// Format bytes to human readable format
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i =
        (bytes == 0 ? 0 : (math.log(bytes) / math.log(1024)).floor()).toInt();
    i = i > suffixes.length - 1 ? suffixes.length - 1 : i;
    final size = bytes / math.pow(1024, i);
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<bool> _isSongDownloadedImpl(String songId) async {
    final task = _getScopedTask('song_$songId');
    return task?.status == DownloadStatus.completed;
  }

  String? _getDownloadedSongPathImpl(String songId) {
    final task = _getScopedTask('song_$songId');
    if (task?.status == DownloadStatus.completed) {
      return _getSongFilePath(songId);
    }
    return null;
  }

  String? _getAnyDownloadedSongPathForAlbumImpl(String albumId) {
    final normalizedAlbumId = albumId.trim();
    if (normalizedAlbumId.isEmpty) return null;

    for (final task in _getScopedQueue()) {
      if (task.status == DownloadStatus.completed &&
          task.albumId == normalizedAlbumId) {
        return _getSongFilePath(task.songId);
      }
    }
    return null;
  }

  double _getTotalDownloadedSizeMBImpl() {
    final tasks = _getScopedQueue();
    int totalBytes = 0;
    for (final task in tasks) {
      if (task.status == DownloadStatus.completed) {
        totalBytes += task.bytesDownloaded;
      }
    }
    return totalBytes / (1024 * 1024);
  }

  int _getCompletedDownloadCountImpl() {
    final tasks = _getScopedQueue();
    return tasks.where((t) => t.status == DownloadStatus.completed).length;
  }

  QueueStats _getQueueStatsImpl() {
    final tasks = _getScopedQueue();
    return _buildQueueStats(tasks);
  }

  Future<int> _pruneOrphanedDownloadsImpl(Set<String> validSongIds) async {
    await _ensureInitialized();

    final tasksToRemove = _getScopedQueue()
        .where((task) => !validSongIds.contains(task.songId))
        .toList();

    if (tasksToRemove.isEmpty) {
      return 0;
    }

    for (final task in tasksToRemove) {
      // Cancel active downloads and remove from queue
      cancelDownload(task.id);
    }

    print('Pruned ${tasksToRemove.length} orphaned downloads');
    return tasksToRemove.length;
  }

  Future<void> _clearAllDownloadsImpl() async {
    await _ensureInitialized();

    // Cancel all active downloads
    for (final token in _activeDownloads.values) {
      token.cancel();
    }
    _activeDownloads.clear();
    _activeProgress.clear(); // Cleanup all progress tracking
    _activeDownloadCount = 0;

    final deletedFileCount = await _clearAllDownloadFilesFromDisk();

    // Clear queue and database
    _queue.clear();
    await _database.clearAllDownloads();
    _persistedTaskSignatures.clear();

    print(
        'All downloads cleared ($deletedFileCount local file${deletedFileCount == 1 ? '' : 's'} removed)');
  }

  Future<void> _deleteAlbumDownloadsImpl(String? albumId) async {
    await _ensureInitialized();

    // Find all tasks matching the albumId
    final tasksToDelete =
        _getScopedQueue().where((task) => task.albumId == albumId).toList();
    if (tasksToDelete.isEmpty) {
      print('No downloads found for album: ${albumId ?? "Singles"}');
      return;
    }

    // Cancel/delete each task
    final songIds = tasksToDelete.map((task) => task.songId).toSet();
    for (final task in tasksToDelete) {
      cancelDownload(task.id);
    }
    var deletedFileCount = 0;
    for (final songId in songIds) {
      if (await _deleteSongFileIfUnreferenced(songId)) {
        deletedFileCount++;
      }
    }

    print(
        'Deleted ${tasksToDelete.length} downloads for album: ${albumId ?? "Singles"} ($deletedFileCount local file${deletedFileCount == 1 ? '' : 's'} removed)');
  }
}
