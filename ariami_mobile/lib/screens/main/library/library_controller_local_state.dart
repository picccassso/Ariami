part of 'library_controller.dart';

extension _LibraryControllerLocalState on LibraryController {
  void _scheduleDownloadedSongsRefresh(List<DownloadTask> tasks) {
    final signature = _buildCompletedDownloadsSignature(tasks);
    if (signature == _lastCompletedDownloadsSignature) return;

    _lastCompletedDownloadsSignature = signature;
    _downloadStateRefreshTimer?.cancel();
    _downloadStateRefreshTimer = Timer(
      const Duration(milliseconds: 150),
      _loadDownloadedSongs,
    );
  }

  void _scheduleCachedSongsRefresh() {
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer(
      const Duration(milliseconds: 250),
      _loadCachedSongs,
    );
  }

  String _buildCompletedDownloadsSignature(List<DownloadTask> queue) {
    final buffer = StringBuffer();
    var completedCount = 0;

    for (final task in queue) {
      if (task.status != DownloadStatus.completed) continue;
      completedCount++;
      buffer
        ..write(task.id)
        ..write(':')
        ..write(task.albumId ?? '')
        ..write('|');
    }

    return '$completedCount#$buffer';
  }

  Future<void> _loadDownloadedSongs([List<DownloadTask>? queueSnapshot]) async {
    final queue = queueSnapshot ?? _downloadManager.queue;
    final downloadedIds = <String>{};
    final albumsWithDownloads = <String>{};
    final albumDownloadCounts = <String, int>{};

    for (final task in queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedIds.add(task.songId);
        if (task.albumId != null) {
          albumsWithDownloads.add(task.albumId!);
          albumDownloadCounts[task.albumId!] =
              (albumDownloadCounts[task.albumId!] ?? 0) + 1;
        }
      }
    }

    final fullyDownloaded = <String>{};
    for (final album in _state.albums) {
      final downloadedCount = albumDownloadCounts[album.id] ?? 0;
      if (downloadedCount >= album.songCount && album.songCount > 0) {
        fullyDownloaded.add(album.id);
      }
    }

    final playlistsWithDownloads = <String>{};
    for (final playlist in _playlistService.playlists) {
      for (final songId in playlist.songIds) {
        if (downloadedIds.contains(songId)) {
          playlistsWithDownloads.add(playlist.id);
          break;
        }
      }
    }

    _lastCompletedDownloadsSignature = _buildCompletedDownloadsSignature(queue);

    final downloadStateUnchanged = _state.downloadedSongIds.length ==
            downloadedIds.length &&
        _state.downloadedSongIds.containsAll(downloadedIds) &&
        _state.albumsWithDownloads.length == albumsWithDownloads.length &&
        _state.albumsWithDownloads.containsAll(albumsWithDownloads) &&
        _state.fullyDownloadedAlbumIds.length == fullyDownloaded.length &&
        _state.fullyDownloadedAlbumIds.containsAll(fullyDownloaded) &&
        _state.playlistsWithDownloads.length == playlistsWithDownloads.length &&
        _state.playlistsWithDownloads.containsAll(playlistsWithDownloads);

    if (downloadStateUnchanged) return;

    _updateState(_state.copyWith(
      downloadedSongIds: downloadedIds,
      albumsWithDownloads: albumsWithDownloads,
      fullyDownloadedAlbumIds: fullyDownloaded,
      playlistsWithDownloads: playlistsWithDownloads,
    ));
  }

  Future<void> _loadCachedSongs() async {
    final allCachedIds = await _cacheManager.getCachedSongIds();

    final cacheStateUnchanged =
        _state.cachedSongIds.length == allCachedIds.length &&
            _state.cachedSongIds.containsAll(allCachedIds);
    if (cacheStateUnchanged) return;

    _updateState(_state.copyWith(cachedSongIds: allCachedIds));
  }

  void _buildLibraryFromDownloads() {
    final queue = _downloadManager.queue;
    final completedTasks =
        queue.where((task) => task.status == DownloadStatus.completed).toList();

    final songs = <Song>[];
    final albumMap = <String, List<DownloadTask>>{};

    for (final task in completedTasks) {
      if (task.albumId != null) {
        albumMap.putIfAbsent(task.albumId!, () => []).add(task);
      } else {
        songs.add(Song(
          id: task.songId,
          title: task.title,
          artist: task.artist,
          album: task.albumName,
          albumId: task.albumId,
          albumArtist: task.albumArtist,
          trackNumber: task.trackNumber,
          discNumber: null,
          year: null,
          genre: null,
          duration: Duration(seconds: task.duration),
          filePath: task.songId,
          fileSize: task.bytesDownloaded,
          modifiedTime: DateTime.now(),
        ));
      }
    }

    final albums = <AlbumModel>[];
    for (final entry in albumMap.entries) {
      final albumId = entry.key;
      final albumTasks = entry.value;
      final firstTask = albumTasks.first;
      final totalDuration =
          albumTasks.fold<int>(0, (sum, task) => sum + task.duration);

      albums.add(AlbumModel(
        id: albumId,
        title: firstTask.albumName ?? '${firstTask.artist} Album',
        artist: firstTask.albumArtist ?? firstTask.artist,
        coverArt: resolveAlbumArtworkUrl(albumId: albumId),
        songCount: albumTasks.length,
        duration: totalDuration,
      ));
    }

    songs.sort((a, b) => a.title.compareTo(b.title));
    albums.sort((a, b) => a.title.compareTo(b.title));

    _updateState(_state.copyWith(
      offlineSongs: songs,
      albums: albums,
      isOfflineMode: true,
    ));
  }
}
