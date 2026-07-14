part of 'download_manager.dart';

extension _DownloadManagerMaintenanceImpl on DownloadManager {
  /// Queue artwork caching for a completed download on the single serialized
  /// artwork worker. Bulk downloads complete faster than tag parsing, so an
  /// unbounded fire-and-forget job per completion piled CPU/disk work on top
  /// of the active transfers; chaining keeps at most one extraction in flight.
  void _queueArtworkCaching(DownloadTask task) {
    _artworkWorkTail = _artworkWorkTail.then(
      (_) => _extractAndCacheArtworkForSong(
        songId: task.songId,
        albumId: task.albumId,
      ),
    );
  }

  /// Cache artwork for a downloaded song (for offline use) by reading embedded
  /// art from the local audio file — no extra HTTP requests to the server.
  ///
  /// Album tracks share one album-level image (full + thumb); no per-song copy
  /// is written because every artwork consumer resolves the album key first
  /// and only falls back to `song_<id>` for albumless singles. The cache-key
  /// check happens before extraction so songs of an already-cached album skip
  /// the tag parse entirely, and the parse itself runs in a short-lived
  /// background isolate to keep megabyte ID3 tags off the UI isolate.
  Future<void> _extractAndCacheArtworkForSong({
    required String songId,
    required String? albumId,
  }) async {
    final cacheManager = CacheManager();
    final localPath = _getSongFilePath(songId);
    if (!await File(localPath).exists()) return;

    try {
      final targetKeys = <String>[];
      if (albumId != null) {
        if (!await cacheManager.isArtworkCached(albumId)) {
          targetKeys.add(albumId);
        }
        final thumbKey = '${albumId}_thumb';
        if (!await cacheManager.isArtworkCached(thumbKey)) {
          targetKeys.add(thumbKey);
        }
      } else {
        final songKey = 'song_$songId';
        if (!await cacheManager.isArtworkCached(songKey)) {
          targetKeys.add(songKey);
        }
      }
      if (targetKeys.isEmpty) return;

      final bytes = await Isolate.run(
        () => LocalArtworkExtractor.extractArtwork(localPath),
      );
      if (bytes == null || bytes.isEmpty) {
        print('[DownloadManager] No embedded artwork for song $songId');
        return;
      }

      for (final key in targetKeys) {
        await cacheManager.cacheArtworkFromBytes(key, bytes);
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

    for (final task in completedTasks) {
      await _extractAndCacheArtworkForSong(
        songId: task.songId,
        albumId: task.albumId,
      );
    }

    await prefs.setBool(backfillKey, true);
    print(
        '[DownloadManager] Local artwork backfill complete: ${completedTasks.length} songs processed');
  }

  /// Get file path for a downloaded song
  String _getSongFilePath(String songId) {
    final downloadPath = _downloadPath;
    if (downloadPath == null || downloadPath.isEmpty) {
      return 'downloads/songs/$songId.mp3';
    }
    return '$downloadPath/songs/$songId.mp3';
  }

  String _getPartialSongFilePath(String songId) {
    return '${_getSongFilePath(songId)}.partial';
  }

  Future<int?> _getPartialSongFileSize(String songId) async {
    final partial = File(_getPartialSongFilePath(songId));
    if (!await partial.exists()) return null;
    return partial.length();
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

  Future<bool> _deletePartialSongFileIfUnreferenced(
    String songId, {
    bool force = false,
  }) async {
    final normalizedSongId = songId.trim();
    if (normalizedSongId.isEmpty) {
      return false;
    }
    if (!force && _queue.queue.any((task) => task.songId == normalizedSongId)) {
      return false;
    }

    final partialFile = File(_getPartialSongFilePath(normalizedSongId));
    if (!await partialFile.exists()) {
      return false;
    }

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await partialFile.delete();
        return true;
      } catch (e) {
        if (attempt == 3) {
          print(
              '[DownloadManager] Failed to delete partial file for song $normalizedSongId: $e');
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
      if (songId != null && knownSongIds.contains(songId)) {
        continue;
      }
      final partialSongId = _songIdFromPartialDownloadFileName(fileName);
      if (partialSongId != null && knownSongIds.contains(partialSongId)) {
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

  String? _songIdFromPartialDownloadFileName(String fileName) {
    const suffix = '.mp3.partial';
    if (fileName.length <= suffix.length ||
        !fileName.toLowerCase().endsWith(suffix)) {
      return null;
    }
    return fileName.substring(0, fileName.length - suffix.length).trim();
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
    // Gate on initialization: downloads are loaded from disk during
    // initialize(), which is deferred until after the first frame. Without this
    // await an early tap (common when offline) sees an empty in-memory queue,
    // resolves the song as not-downloaded, and playback fails until a later
    // retry happens to run after init completes.
    await _ensureInitialized();
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

    _queue.beginBatch();
    try {
      for (final task in tasksToRemove) {
        // Cancel active downloads and remove from queue
        cancelDownload(task.id);
      }
    } finally {
      _queue.endBatch();
    }

    print('Pruned ${tasksToRemove.length} orphaned downloads');
    return tasksToRemove.length;
  }

  Future<int> _pruneOrphanedIncompleteDownloadsImpl(
    Set<String> validSongIds,
  ) async {
    await _ensureInitialized();

    final tasksToRemove = _getScopedQueue()
        .where((task) =>
            task.status != DownloadStatus.completed &&
            !validSongIds.contains(task.songId))
        .toList();
    _queue.beginBatch();
    try {
      for (final task in tasksToRemove) {
        cancelDownload(task.id);
      }
    } finally {
      _queue.endBatch();
    }
    return tasksToRemove.length;
  }

  Future<int> _relinkOrphanedCompletedDownloadsImpl({
    required List<SongModel> librarySongs,
    required List<AlbumModel> libraryAlbums,
  }) async {
    await _ensureInitialized();
    if (librarySongs.isEmpty) return 0;

    final librarySongIds = librarySongs.map((song) => song.id).toSet();
    final albumsById = {for (final album in libraryAlbums) album.id: album};
    final orphanedTasks = _getScopedQueue()
        .where((task) =>
            task.status == DownloadStatus.completed &&
            !librarySongIds.contains(task.songId))
        .toList();
    var relinkedCount = 0;

    for (final task in orphanedTasks) {
      final matches = librarySongs
          .where((song) => _downloadTaskMatchesSong(task, song, albumsById))
          .where((song) =>
              !_queue.queue.any((queuedTask) => queuedTask.songId == song.id))
          .toList();
      if (matches.length != 1) continue;

      final song = matches.single;
      if (!await _renameCompletedSongFile(task.songId, song.id)) continue;

      final replacement = _buildRelinkedDownloadTask(task, song, albumsById);
      if (!_queue.replaceTask(task.id, replacement)) {
        await _renameCompletedSongFile(song.id, task.songId);
        continue;
      }
      _invalidateScopedQueueCache();

      if (sessionTaskIds.remove(task.id)) {
        sessionTaskIds.add(replacement.id);
      }
      _queueArtworkCaching(replacement);
      relinkedCount++;
    }

    if (relinkedCount > 0) {
      print('[DownloadManager] Relinked $relinkedCount completed download(s)');
    }
    return relinkedCount;
  }

  Future<Map<String, String>> _migrateDownloadAlbumIdsImpl({
    required List<SongModel> librarySongs,
    required List<AlbumModel> libraryAlbums,
  }) async {
    await _ensureInitialized();
    if (librarySongs.isEmpty) return const {};

    final songsById = {for (final song in librarySongs) song.id: song};
    final albumsById = {for (final album in libraryAlbums) album.id: album};
    final tasks = _getScopedQueue()
        .where((task) => task.status == DownloadStatus.completed)
        .toList();
    var migratedCount = 0;
    // Exact old -> new album ID pairs observed while remapping, so callers can
    // migrate other album-keyed state (pins, recents) without guessing.
    final albumIdRemap = <String, String>{};

    _queue.beginBatch();
    try {
      for (final task in tasks) {
        // Only remap downloads whose song still exists in the library; songs
        // that genuinely vanished are handled by the orphan-relink pass.
        final song = songsById[task.songId];
        if (song == null) continue;
        if (song.albumId == task.albumId) continue;

        final album =
            song.albumId == null ? null : albumsById[song.albumId];
        final replacement =
            _buildAlbumIdMigratedTask(task, song.albumId, album);
        if (_queue.replaceTask(task.id, replacement)) {
          migratedCount++;
          if (task.albumId != null && song.albumId != null) {
            albumIdRemap[task.albumId!] = song.albumId!;
          }
        }
      }
    } finally {
      _queue.endBatch();
    }

    if (migratedCount > 0) {
      _invalidateScopedQueueCache();
      print('[DownloadManager] Migrated album IDs for $migratedCount '
          'completed download(s)');
    }
    return albumIdRemap;
  }

  Future<int> _refreshDownloadAlbumMetadataImpl({
    required List<AlbumModel> libraryAlbums,
    List<SongModel> librarySongs = const <SongModel>[],
  }) async {
    await _ensureInitialized();
    if (libraryAlbums.isEmpty) return 0;

    final albumsById = {for (final album in libraryAlbums) album.id: album};
    final albumIdBySongId = {
      for (final song in librarySongs)
        if (song.albumId != null) song.id: song.albumId!,
    };
    final tasks = _getScopedQueue().toList();
    var refreshedCount = 0;

    _queue.beginBatch();
    try {
      for (final task in tasks) {
        final albumId = task.albumId ?? albumIdBySongId[task.songId];
        final album = albumId == null ? null : albumsById[albumId];
        if (album == null ||
            (task.albumId == album.id &&
                task.albumName == album.title &&
                task.albumArtist == album.artist &&
                (album.coverArt == null || task.albumArt == album.coverArt))) {
          continue;
        }

        final replacement = _buildDownloadTaskWithAlbumMetadata(
          task,
          album,
          albumId: album.id,
        );
        if (_queue.replaceTask(task.id, replacement)) {
          refreshedCount++;
        }
      }
    } finally {
      _queue.endBatch();
    }

    if (refreshedCount > 0) {
      _invalidateScopedQueueCache();
    }
    return refreshedCount;
  }

  bool _downloadTaskMatchesSong(
    DownloadTask task,
    SongModel song,
    Map<String, AlbumModel> albumsById,
  ) {
    var hasSupportingMetadata = false;
    if (_normalizeDownloadMetadata(task.title) !=
            _normalizeDownloadMetadata(song.title) ||
        _normalizeDownloadMetadata(task.artist) !=
            _normalizeDownloadMetadata(song.artist)) {
      return false;
    }
    if (task.duration > 0 &&
        song.duration > 0 &&
        (task.duration - song.duration).abs() > 3) {
      return false;
    }
    if (task.duration > 0 && song.duration > 0) {
      hasSupportingMetadata = true;
    }
    if (task.trackNumber != null && task.trackNumber != song.trackNumber) {
      return false;
    }
    if (task.trackNumber != null) {
      hasSupportingMetadata = true;
    }
    if ((task.albumId == null) != (song.albumId == null)) {
      return false;
    }

    final album = song.albumId == null ? null : albumsById[song.albumId];
    if (!_optionalDownloadMetadataMatches(task.albumName, album?.title) ||
        !_optionalAlbumArtistMatches(task.albumArtist, album?.artist)) {
      return false;
    }
    if ((task.albumName?.trim().isNotEmpty ?? false) ||
        (task.albumArtist?.trim().isNotEmpty ?? false)) {
      hasSupportingMetadata = true;
    }
    return hasSupportingMetadata;
  }

  bool _optionalDownloadMetadataMatches(String? expected, String? actual) {
    if (expected == null || expected.trim().isEmpty) return true;
    if (actual == null || actual.trim().isEmpty) return false;
    return _normalizeDownloadMetadata(expected) ==
        _normalizeDownloadMetadata(actual);
  }

  bool _optionalAlbumArtistMatches(String? expected, String? actual) {
    if (expected == null || expected.trim().isEmpty) return true;
    if (_normalizeDownloadMetadata(expected) == 'various artists') return true;
    return _optionalDownloadMetadataMatches(expected, actual);
  }

  String _normalizeDownloadMetadata(String value) => value.trim().toLowerCase();

  Future<bool> _renameCompletedSongFile(
      String oldSongId, String newSongId) async {
    if (oldSongId == newSongId) return true;

    final oldFile = File(_getSongFilePath(oldSongId));
    final newFile = File(_getSongFilePath(newSongId));
    if (!await oldFile.exists() || await newFile.exists()) return false;

    try {
      await oldFile.rename(newFile.path);
      return true;
    } catch (e) {
      print(
        '[DownloadManager] Failed to relink local file $oldSongId -> $newSongId: $e',
      );
      return false;
    }
  }

  DownloadTask _buildRelinkedDownloadTask(
    DownloadTask task,
    SongModel song,
    Map<String, AlbumModel> albumsById,
  ) {
    final album = song.albumId == null ? null : albumsById[song.albumId];
    final apiClient = ConnectionService().apiClient;
    return DownloadTask(
      id: 'song_${song.id}',
      songId: song.id,
      serverId: task.serverId,
      userId: task.userId,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      albumName: album?.title ?? task.albumName,
      albumArtist: album?.artist ?? task.albumArtist,
      albumArt: task.albumArt,
      downloadUrl: apiClient == null
          ? task.downloadUrl
          : _buildLegacyDownloadUrl(
              apiClient: apiClient,
              songId: song.id,
              downloadQuality: task.downloadQuality,
              downloadOriginal: task.downloadOriginal,
            ),
      downloadQuality: task.downloadQuality,
      downloadOriginal: task.downloadOriginal,
      duration: song.duration,
      trackNumber: song.trackNumber,
      status: DownloadStatus.completed,
      progress: task.progress,
      bytesDownloaded: task.bytesDownloaded,
      totalBytes: task.totalBytes,
      errorMessage: task.errorMessage,
      retryCount: task.retryCount,
      nativeBackend: task.nativeBackend,
      nativeTaskId: task.nativeTaskId,
    );
  }

  DownloadTask _buildAlbumIdMigratedTask(
    DownloadTask task,
    String? newAlbumId,
    AlbumModel? album,
  ) {
    return DownloadTask(
      id: task.id,
      songId: task.songId,
      serverId: task.serverId,
      userId: task.userId,
      title: task.title,
      artist: task.artist,
      albumId: newAlbumId,
      albumName: album?.title ?? task.albumName,
      albumArtist: album?.artist ?? task.albumArtist,
      albumArt: album?.coverArt ?? task.albumArt,
      downloadUrl: task.downloadUrl,
      downloadQuality: task.downloadQuality,
      downloadOriginal: task.downloadOriginal,
      duration: task.duration,
      trackNumber: task.trackNumber,
      status: task.status,
      progress: task.progress,
      bytesDownloaded: task.bytesDownloaded,
      totalBytes: task.totalBytes,
      errorMessage: task.errorMessage,
      retryCount: task.retryCount,
      nativeBackend: task.nativeBackend,
      nativeTaskId: task.nativeTaskId,
    );
  }

  DownloadTask _buildDownloadTaskWithAlbumMetadata(
    DownloadTask task,
    AlbumModel album, {
    String? albumId,
  }) {
    return DownloadTask(
      id: task.id,
      songId: task.songId,
      serverId: task.serverId,
      userId: task.userId,
      title: task.title,
      artist: task.artist,
      albumId: albumId ?? task.albumId,
      albumName: album.title,
      albumArtist: album.artist,
      albumArt: album.coverArt ?? task.albumArt,
      downloadUrl: task.downloadUrl,
      downloadQuality: task.downloadQuality,
      downloadOriginal: task.downloadOriginal,
      duration: task.duration,
      trackNumber: task.trackNumber,
      status: task.status,
      progress: task.progress,
      bytesDownloaded: task.bytesDownloaded,
      totalBytes: task.totalBytes,
      errorMessage: task.errorMessage,
      retryCount: task.retryCount,
      nativeBackend: task.nativeBackend,
      nativeTaskId: task.nativeTaskId,
    );
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
    _queue.beginBatch();
    try {
      for (final task in tasksToDelete) {
        cancelDownload(task.id);
      }
    } finally {
      _queue.endBatch();
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

  Future<void> _deleteSongDownloadsImpl(Iterable<String> songIds) async {
    await _ensureInitialized();

    final ids = songIds.toSet();
    final tasksToDelete =
        _getScopedQueue().where((task) => ids.contains(task.songId)).toList();
    if (tasksToDelete.isEmpty) return;

    _queue.beginBatch();
    try {
      for (final task in tasksToDelete) {
        cancelDownload(task.id);
      }
    } finally {
      _queue.endBatch();
    }
    for (final songId in ids) {
      await _deleteSongFileIfUnreferenced(songId);
    }
  }
}
