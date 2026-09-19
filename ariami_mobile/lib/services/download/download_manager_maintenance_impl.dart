part of 'download_manager.dart';

extension _DownloadManagerMaintenanceImpl on DownloadManager {
  /// Queue artwork caching for a completed download on the single serialized
  /// artwork worker. Bulk downloads complete faster than tag parsing, so an
  /// unbounded fire-and-forget job per completion piled CPU/disk work on top
  /// of the active transfers; chaining keeps at most one extraction in flight.
  void _queueArtworkCaching(DownloadTask task) {
    _artworkWorkTail = _artworkWorkTail.then(
      (_) => _cacheArtworkForDownloadedSong(
        songId: task.songId,
        albumId: task.albumId,
        artworkUrl: task.albumArt,
        downloadOriginal: task.downloadOriginal,
        fileExtension: task.downloadFileExtension,
      ),
    );
  }

  void _queueArtworkBackfill() {
    _artworkWorkTail = _artworkWorkTail.then(
      (_) => _backfillArtworkForExistingDownloads(),
    );
  }

  /// Cache full-resolution artwork for a downloaded song.
  ///
  /// Transcoded downloads prefer the server artwork endpoint because audio
  /// quality and image quality are separate concerns: Opus preserves text
  /// comments but does not carry the source file's embedded picture. Original
  /// downloads still use their embedded image first, avoiding an extra request.
  /// Either path stores the full image under the album/song key used by detail
  /// views. Thumbnail views can downscale it or keep their separate 200px cache.
  Future<bool> _cacheArtworkForDownloadedSong({
    required String songId,
    required String? albumId,
    required String artworkUrl,
    required bool downloadOriginal,
    String? fileExtension,
  }) async {
    final cacheManager = CacheManager();
    final localPath = _getSongFilePath(songId, fileExtension: fileExtension);
    if (!await File(localPath).exists()) return true;

    try {
      final primaryKey = albumId ?? 'song_$songId';
      if (await cacheManager.isArtworkCached(primaryKey)) return true;

      final resolvedArtworkUrl = _resolveFullArtworkUrl(
        artworkUrl: artworkUrl,
        albumId: albumId,
        songId: songId,
      );
      if (!downloadOriginal && resolvedArtworkUrl != null) {
        final cachedPath = await cacheManager.cacheArtwork(
          primaryKey,
          resolvedArtworkUrl,
        );
        if (cachedPath != null) return true;
      }

      final bytes = await Isolate.run(
        () => LocalArtworkExtractor.extractArtwork(localPath),
      );
      if (bytes != null && bytes.isNotEmpty) {
        final targetKeys = <String>[primaryKey];
        if (albumId != null) {
          final thumbKey = '${albumId}_thumb';
          if (!await cacheManager.isArtworkCached(thumbKey)) {
            targetKeys.add(thumbKey);
          }
        }
        for (final key in targetKeys) {
          await cacheManager.cacheArtworkFromBytes(key, bytes);
        }
        return true;
      }

      if (resolvedArtworkUrl != null) {
        final cachedPath = await cacheManager.cacheArtwork(
          primaryKey,
          resolvedArtworkUrl,
        );
        if (cachedPath != null) return true;
      }

      print('[DownloadManager] No full artwork available for song $songId');
      return resolvedArtworkUrl == null;
    } catch (e) {
      // Don't fail the download if artwork caching fails
      print('[DownloadManager] Failed to cache artwork: $e');
      return false;
    }
  }

  String? _resolveFullArtworkUrl({
    required String artworkUrl,
    required String? albumId,
    required String songId,
  }) {
    final currentBaseUrl = ConnectionService().apiClient?.baseUrl;
    if (currentBaseUrl != null && currentBaseUrl.isNotEmpty) {
      final normalizedBaseUrl = currentBaseUrl.endsWith('/')
          ? currentBaseUrl.substring(0, currentBaseUrl.length - 1)
          : currentBaseUrl;
      final normalizedAlbumId = albumId?.trim();
      final endpoint = normalizedAlbumId != null && normalizedAlbumId.isNotEmpty
          ? 'artwork/${Uri.encodeComponent(normalizedAlbumId)}'
          : 'song-artwork/${Uri.encodeComponent(songId)}';
      return '$normalizedBaseUrl/$endpoint';
    }

    final trimmed = artworkUrl.trim();
    if (trimmed.isEmpty) return null;
    final resolved = ConnectionService().resolveServerUrl(trimmed);
    if (resolved == null || resolved.isEmpty) return null;

    final uri = Uri.tryParse(resolved);
    if (uri == null) return resolved;
    final query = Map<String, String>.from(uri.queryParameters)..remove('size');
    return uri.replace(queryParameters: query).toString();
  }

  /// One-time backfill: extract embedded art from already-downloaded files
  /// and repair transcoded downloads from the full server artwork endpoint.
  /// If the server is unavailable, leave the marker unset so reconnect can
  /// retry instead of permanently accepting a thumbnail-only offline cache.
  Future<void> _backfillArtworkForExistingDownloads() async {
    const backfillKey = 'artwork_backfill_v5_full_resolution';
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(backfillKey) == true) {
      return;
    }

    final uniqueTasks = <String, DownloadTask>{};
    for (final task in _queue.queue) {
      if (task.status != DownloadStatus.completed) continue;
      final artworkKey = task.albumId ?? 'song_${task.songId}';
      uniqueTasks.putIfAbsent(artworkKey, () => task);
    }
    final completedTasks = uniqueTasks.values.toList(growable: false);

    if (completedTasks.isEmpty) {
      await prefs.setBool(backfillKey, true);
      return;
    }

    print('[DownloadManager] Starting artwork backfill for '
        '${completedTasks.length} downloaded covers...');

    var retryNeeded = false;
    for (final task in completedTasks) {
      final cached = await _cacheArtworkForDownloadedSong(
        songId: task.songId,
        albumId: task.albumId,
        artworkUrl: task.albumArt,
        downloadOriginal: task.downloadOriginal,
        fileExtension: task.downloadFileExtension,
      );
      retryNeeded |= !cached;
    }

    if (!retryNeeded) {
      await prefs.setBool(backfillKey, true);
    }
    print('[DownloadManager] Artwork backfill complete: '
        '${completedTasks.length} unique covers processed'
        '${retryNeeded ? ' (will retry after reconnect)' : ''}');
  }

  /// Get file path for a downloaded song
  String _getSongFilePath(String songId, {String? fileExtension}) {
    var extension = fileExtension ?? 'mp3';
    if (fileExtension == null) {
      for (final task in _queue.queue) {
        if (task.songId == songId) {
          extension = task.downloadFileExtension;
          break;
        }
      }
    }
    final downloadPath = _downloadPath;
    if (downloadPath == null || downloadPath.isEmpty) {
      return 'downloads/songs/$songId.$extension';
    }
    return '$downloadPath/songs/$songId.$extension';
  }

  String _getPartialSongFilePath(String songId, {String? fileExtension}) {
    return '${_getSongFilePath(songId, fileExtension: fileExtension)}.partial';
  }

  Future<int?> _getPartialSongFileSize(
    String songId, {
    String? fileExtension,
  }) async {
    final partial =
        File(_getPartialSongFilePath(songId, fileExtension: fileExtension));
    if (!await partial.exists()) return null;
    return partial.length();
  }

  Future<bool> _deleteFileWithRetry(File file, String identifier) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        if (!await file.exists()) return true;
        await file.delete();
        return true;
      } on FileSystemException catch (e) {
        if (!await file.exists()) return true;
        if (attempt == 3) {
          print(
              '[DownloadManager] Failed to delete file ${file.path} for $identifier: $e');
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } catch (e) {
        if (attempt == 3) {
          print(
              '[DownloadManager] Failed to delete file ${file.path} for $identifier: $e');
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return false;
  }

  Future<bool> _deleteSongFileIfUnreferenced(
    String songId, {
    String? fileExtension,
  }) async {
    final normalizedSongId = songId.trim();
    if (normalizedSongId.isEmpty) {
      return false;
    }
    if (_queue.queue.any((task) => task.songId == normalizedSongId)) {
      return false;
    }

    var deleted = false;
    if (fileExtension != null && fileExtension.isNotEmpty) {
      final songFile = File(
        _getSongFilePath(normalizedSongId, fileExtension: fileExtension),
      );
      if (await songFile.exists()) {
        deleted = await _deleteFileWithRetry(songFile, normalizedSongId);
      }
    }

    if (!deleted) {
      final downloadPath = _downloadPath;
      if (downloadPath != null && downloadPath.isNotEmpty) {
        final songsDir = Directory('$downloadPath/songs');
        if (await songsDir.exists()) {
          await for (final entity in songsDir.list(followLinks: false)) {
            if (entity is File) {
              final fileName = entity.path.split(Platform.pathSeparator).last;
              if (_songIdFromDownloadFileName(fileName) == normalizedSongId) {
                if (await _deleteFileWithRetry(entity, normalizedSongId)) {
                  deleted = true;
                }
              }
            }
          }
        }
      }
    }

    return deleted;
  }

  Future<bool> _deletePartialSongFileIfUnreferenced(
    String songId, {
    bool force = false,
    String? fileExtension,
  }) async {
    final normalizedSongId = songId.trim();
    if (normalizedSongId.isEmpty) {
      return false;
    }
    if (!force && _queue.queue.any((task) => task.songId == normalizedSongId)) {
      return false;
    }

    var deleted = false;
    if (fileExtension != null && fileExtension.isNotEmpty) {
      final partialFile = File(
        _getPartialSongFilePath(
          normalizedSongId,
          fileExtension: fileExtension,
        ),
      );
      if (await partialFile.exists()) {
        deleted = await _deleteFileWithRetry(partialFile, normalizedSongId);
      }
    }

    if (!deleted) {
      final downloadPath = _downloadPath;
      if (downloadPath != null && downloadPath.isNotEmpty) {
        final songsDir = Directory('$downloadPath/songs');
        if (await songsDir.exists()) {
          await for (final entity in songsDir.list(followLinks: false)) {
            if (entity is File) {
              final fileName = entity.path.split(Platform.pathSeparator).last;
              if (_songIdFromPartialDownloadFileName(fileName) ==
                  normalizedSongId) {
                if (await _deleteFileWithRetry(entity, normalizedSongId)) {
                  deleted = true;
                }
              }
            }
          }
        }
      }
    }

    return deleted;
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

  static final RegExp _validExtensionRegExp = RegExp(r'^[a-z0-9]{1,8}$');

  Future<int> _cleanupStaleDownloadFiles() async {
    final downloadPath = _downloadPath;
    if (downloadPath == null || downloadPath.isEmpty) {
      return 0;
    }

    final songsDir = Directory('$downloadPath/songs');
    if (!await songsDir.exists()) {
      return 0;
    }

    final tasksBySongId = <String, List<DownloadTask>>{};
    for (final task in _queue.queue) {
      final songId = task.songId.trim();
      if (songId.isNotEmpty) {
        tasksBySongId.putIfAbsent(songId, () => []).add(task);
      }
    }
    var removedCount = 0;

    await for (final entity in songsDir.list(followLinks: false)) {
      if (entity is Directory) {
        // An untracked directory is not proof that its contents are disposable.
        // Clear All remains the explicit destructive cleanup path.
        continue;
      }
      if (entity is! File) {
        continue;
      }

      final fileName = entity.path.split(Platform.pathSeparator).last;
      final partialSongId = _songIdFromPartialDownloadFileName(fileName);
      if (partialSongId != null) {
        final tasks = tasksBySongId[partialSongId];
        if (tasks == null) {
          // A missing queue row can be a persistence failure after a completed
          // transfer. Preserve unknown files rather than destroying evidence.
          continue;
        }
        final shouldKeepPartial = tasks.any((t) {
          if (t.status == DownloadStatus.completed) return false;
          final ext = t.downloadFileExtension.trim().toLowerCase();
          return fileName == '$partialSongId.$ext.partial' ||
              fileName == '$partialSongId.partial';
        });
        if (shouldKeepPartial) {
          continue;
        }
        final hasDurableFinalFile = tasks.any((t) {
          if (t.status != DownloadStatus.completed) return false;
          final ext = t.downloadFileExtension.trim().toLowerCase();
          return File('$downloadPath/songs/$partialSongId.$ext').existsSync();
        });
        if (!hasDurableFinalFile) {
          continue;
        }
      } else {
        final songId = _songIdFromDownloadFileName(fileName);
        if (songId != null) {
          final tasks = tasksBySongId[songId];
          if (tasks != null) {
            final shouldKeepFile = tasks.any((t) {
              if (t.status != DownloadStatus.completed) return false;
              final ext = t.downloadFileExtension.trim().toLowerCase();
              return fileName == '$songId.$ext';
            });
            if (shouldKeepFile) {
              continue;
            }
          }
        }
        // Never infer that a completed-looking file is disposable merely from
        // a missing/mismatched queue row. This was deleting successfully
        // downloaded libraries after an interrupted persistence flush.
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
    final lower = fileName.toLowerCase();
    if (lower.startsWith('.') || lower.endsWith('.partial')) {
      return null;
    }
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return null;
    }
    final ext = lower.substring(dotIndex + 1);
    if (!_validExtensionRegExp.hasMatch(ext)) {
      return null;
    }
    final songId = fileName.substring(0, dotIndex).trim();
    return songId.isEmpty ? null : songId;
  }

  String? _songIdFromPartialDownloadFileName(String fileName) {
    const suffix = '.partial';
    final lower = fileName.toLowerCase();
    if (fileName.length <= suffix.length || !lower.endsWith(suffix)) {
      return null;
    }
    final baseName =
        fileName.substring(0, fileName.length - suffix.length).trim();
    if (baseName.isEmpty || baseName.startsWith('.')) {
      return null;
    }
    final dotIndex = baseName.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < baseName.length - 1) {
      final ext = baseName.substring(dotIndex + 1).toLowerCase();
      if (_validExtensionRegExp.hasMatch(ext)) {
        final candidateId = baseName.substring(0, dotIndex).trim();
        if (candidateId.isNotEmpty) {
          return candidateId;
        }
      }
    }
    return baseName;
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
      return _getSongFilePath(
        songId,
        fileExtension: task!.downloadFileExtension,
      );
    }
    return null;
  }

  String? _getAnyDownloadedSongPathForAlbumImpl(String albumId) {
    final normalizedAlbumId = albumId.trim();
    if (normalizedAlbumId.isEmpty) return null;

    for (final task in _getScopedQueue()) {
      if (task.status == DownloadStatus.completed &&
          task.albumId == normalizedAlbumId) {
        return _getSongFilePath(
          task.songId,
          fileExtension: task.downloadFileExtension,
        );
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
      if (!await _renameCompletedSongFile(
        task.songId,
        song.id,
        fileExtension: task.downloadFileExtension,
      )) {
        continue;
      }

      final replacement = _buildRelinkedDownloadTask(task, song, albumsById);
      if (!_queue.replaceTask(task.id, replacement)) {
        await _renameCompletedSongFile(
          song.id,
          task.songId,
          fileExtension: task.downloadFileExtension,
        );
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

        final album = song.albumId == null ? null : albumsById[song.albumId];
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
    if (libraryAlbums.isEmpty && librarySongs.isEmpty) return 0;

    final albumsById = {for (final album in libraryAlbums) album.id: album};
    final songsById = {for (final song in librarySongs) song.id: song};
    final albumIdBySongId = {
      for (final song in librarySongs)
        if (song.albumId != null) song.id: song.albumId!,
    };
    final tasks = _getScopedQueue().toList();
    var refreshedCount = 0;

    _queue.beginBatch();
    try {
      for (final task in tasks) {
        final song = songsById[task.songId];
        final albumId = task.albumId ?? albumIdBySongId[task.songId];
        final album = albumId == null ? null : albumsById[albumId];
        final genreChanged = song?.genre != null && task.genre != song!.genre;
        final albumChanged = album != null &&
            !(task.albumId == album.id &&
                task.albumName == album.title &&
                task.albumArtist == album.artist &&
                (album.coverArt == null || task.albumArt == album.coverArt));
        if (!genreChanged && !albumChanged) {
          continue;
        }

        final replacement = _buildDownloadTaskWithMetadata(
          task,
          album: album,
          albumId: album?.id,
          genre: song?.genre,
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
    String oldSongId,
    String newSongId, {
    String? fileExtension,
  }) async {
    if (oldSongId == newSongId) return true;

    final oldFile =
        File(_getSongFilePath(oldSongId, fileExtension: fileExtension));
    final newFile =
        File(_getSongFilePath(newSongId, fileExtension: fileExtension));
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
      genre: song.genre,
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
      downloadFileExtension: task.downloadFileExtension,
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
      downloadEtag: task.downloadEtag,
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
      genre: task.genre,
      albumId: newAlbumId,
      albumName: album?.title ?? task.albumName,
      albumArtist: album?.artist ?? task.albumArtist,
      albumArt: album?.coverArt ?? task.albumArt,
      downloadUrl: task.downloadUrl,
      downloadQuality: task.downloadQuality,
      downloadOriginal: task.downloadOriginal,
      downloadFileExtension: task.downloadFileExtension,
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
      downloadEtag: task.downloadEtag,
    );
  }

  DownloadTask _buildDownloadTaskWithMetadata(
    DownloadTask task, {
    AlbumModel? album,
    String? albumId,
    String? genre,
  }) {
    return DownloadTask(
      id: task.id,
      songId: task.songId,
      serverId: task.serverId,
      userId: task.userId,
      title: task.title,
      artist: task.artist,
      genre: genre ?? task.genre,
      albumId: albumId ?? task.albumId,
      albumName: album?.title ?? task.albumName,
      albumArtist: album?.artist ?? task.albumArtist,
      albumArt: album?.coverArt ?? task.albumArt,
      downloadUrl: task.downloadUrl,
      downloadQuality: task.downloadQuality,
      downloadOriginal: task.downloadOriginal,
      downloadFileExtension: task.downloadFileExtension,
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
      downloadEtag: task.downloadEtag,
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
    _slotHolders.clear();

    final deletedFileCount = await _clearAllDownloadFilesFromDisk();

    // Clear queue and database
    _queue.clear();
    await _database.clearAllDownloads();
    _persistedTaskSignatures.clear();
    clearDownloadSession();

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
    _queue.beginBatch();
    try {
      for (final task in tasksToDelete) {
        cancelDownload(task.id);
      }
    } finally {
      _queue.endBatch();
    }
    var deletedFileCount = 0;
    for (final task in tasksToDelete) {
      if (await _deleteSongFileIfUnreferenced(
        task.songId,
        fileExtension: task.downloadFileExtension,
      )) {
        deletedFileCount++;
      }
      await _deletePartialSongFileIfUnreferenced(
        task.songId,
        force: true,
        fileExtension: task.downloadFileExtension,
      );
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
    for (final task in tasksToDelete) {
      await _deleteSongFileIfUnreferenced(
        task.songId,
        fileExtension: task.downloadFileExtension,
      );
      await _deletePartialSongFileIfUnreferenced(
        task.songId,
        force: true,
        fileExtension: task.downloadFileExtension,
      );
    }
  }
}
