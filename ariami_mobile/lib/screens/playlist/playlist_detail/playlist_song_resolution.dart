part of '../playlist_detail_screen.dart';

/// Resolves playlist ids into display/playback metadata without owning UI.
abstract class _PlaylistSongResolutionState extends _PlaylistDetailState {
  /// Resolve song IDs to SongModel objects
  @override
  Future<List<SongModel>> _resolveSongs(List<String> songIds) async {
    if (songIds.isEmpty) {
      return [];
    }

    if (_offlineService.isOffline || _connectionService.apiClient == null) {
      return await _resolveSongsFromDownloads(songIds);
    }

    final songs = await _resolveSongsFromLocalMetadata(songIds);
    _fetchAlbumInfoInBackground();

    return songs;
  }

  /// Fetch album info from server in background
  void _fetchAlbumInfoInBackground() {
    unawaited(() async {
      try {
        final albums = await _connectionService.libraryReadFacade.getAlbums();

        for (final album in albums) {
          _albumInfoMap[album.id] = (name: album.title, artist: album.artist);
        }

        for (final entry in _completedDownloadTasksByAlbum().entries) {
          final firstTask = entry.value.first;
          if (firstTask.albumName != null &&
              !_albumInfoMap.containsKey(entry.key)) {
            _albumInfoMap[entry.key] = (
              name: firstTask.albumName!,
              artist: resolveDownloadedAlbumArtist(entry.value),
            );
          }
        }

        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        print('[PlaylistDetailScreen] Background album info load failed: $e');
      }
    }());
  }

  Future<List<SongModel>> _loadLibrarySongsForMetadata() async {
    try {
      final localSongs = await _libraryRepository.getSongs();
      if (localSongs.isNotEmpty) {
        return localSongs;
      }
    } catch (e) {
      print(
          '[PlaylistDetailScreen] Local repository song metadata load failed: $e');
    }

    try {
      return await _connectionService.libraryReadFacade.getSongs();
    } catch (e) {
      print('[PlaylistDetailScreen] Facade song metadata load failed: $e');
      return const <SongModel>[];
    }
  }

  @override
  List<SongModel> _buildSongsFromStoredMetadata(
    PlaylistModel playlist, {
    Map<String, SongModel> preferredSongsById = const <String, SongModel>{},
  }) {
    final downloadedSongs = _buildDownloadedSongsMap();

    return playlist.songIds.map((id) {
      final downloadedSong = downloadedSongs[id];
      if (downloadedSong != null) {
        return downloadedSong;
      }

      final preferredSong = preferredSongsById[id];
      final cachedTitle = playlist.songTitles[id];
      final cachedArtist = playlist.songArtists[id];
      final cachedDuration = playlist.songDurations[id];
      final isUnresolved =
          (cachedTitle == null || cachedTitle.isEmpty) && preferredSong == null;

      return SongModel(
        id: id,
        title: (cachedTitle != null && cachedTitle.isNotEmpty)
            ? cachedTitle
            : (preferredSong?.title ?? _missingTrackTitle(isUnresolved)),
        artist: (cachedArtist != null && cachedArtist.isNotEmpty)
            ? cachedArtist
            : (preferredSong?.artist ?? 'Unknown Artist'),
        albumId: playlist.songAlbumIds[id] ?? preferredSong?.albumId,
        duration: (cachedDuration != null && cachedDuration > 0)
            ? cachedDuration
            : (preferredSong?.duration ?? 0),
        trackNumber: preferredSong?.trackNumber,
      );
    }).toList();
  }

  String _missingTrackTitle(bool isUnresolved) {
    return isUnresolved ? 'Missing from library' : 'Unknown Song';
  }

  Map<String, SongModel> _buildDownloadedSongsMap() {
    final downloadedSongs = <String, SongModel>{};

    for (final task in _downloadManager.queue) {
      if (task.status != DownloadStatus.completed) {
        continue;
      }

      downloadedSongs[task.songId] = SongModel(
        id: task.songId,
        title: task.title,
        artist: task.artist,
        albumId: task.albumId,
        duration: task.duration,
        trackNumber: task.trackNumber,
      );
    }

    for (final entry in _completedDownloadTasksByAlbum().entries) {
      final firstTask = entry.value.first;
      if (firstTask.albumName != null) {
        _albumInfoMap[entry.key] = (
          name: firstTask.albumName!,
          artist: resolveDownloadedAlbumArtist(entry.value),
        );
      }
    }

    return downloadedSongs;
  }

  Map<String, List<DownloadTask>> _completedDownloadTasksByAlbum() {
    final tasksByAlbum = <String, List<DownloadTask>>{};
    for (final task in _downloadManager.queue) {
      if (task.status != DownloadStatus.completed || task.albumId == null) {
        continue;
      }
      tasksByAlbum.putIfAbsent(task.albumId!, () => []).add(task);
    }
    return tasksByAlbum;
  }

  @override
  bool _needsLibrarySongMetadata(List<SongModel> songs) {
    return songs.any(
      (song) =>
          song.duration <= 0 ||
          song.title.isEmpty ||
          song.title == 'Unknown Song' ||
          song.title == 'Missing from library' ||
          song.artist.isEmpty ||
          song.artist == 'Unknown Artist',
    );
  }

  /// Build SongModel objects from playlist's locally-stored metadata
  Future<List<SongModel>> _resolveSongsFromLocalMetadata(
      List<String> songIds) async {
    final playlist = _playlist;
    if (playlist == null) {
      return const <SongModel>[];
    }

    final provisionalSongs = _buildSongsFromStoredMetadata(playlist);
    if (!_needsLibrarySongMetadata(provisionalSongs)) {
      return provisionalSongs;
    }

    final librarySongs = await _loadLibrarySongsForMetadata();
    final provisionalSongsById = {
      for (final song in provisionalSongs) song.id: song,
    };
    final librarySongsById = {for (final song in librarySongs) song.id: song};

    return songIds.map((id) {
      final provisionalSong = provisionalSongsById[id];
      final librarySong = librarySongsById[id];

      if (provisionalSong == null) {
        return librarySong ??
            SongModel(
              id: id,
              title: 'Missing from library',
              artist: 'Unknown Artist',
              duration: 0,
            );
      }

      if (librarySong == null) {
        return provisionalSong;
      }

      return SongModel(
        id: id,
        title: provisionalSong.title == 'Unknown Song' ||
                provisionalSong.title == 'Missing from library'
            ? librarySong.title
            : provisionalSong.title,
        artist: provisionalSong.artist == 'Unknown Artist'
            ? librarySong.artist
            : provisionalSong.artist,
        albumId: provisionalSong.albumId ?? librarySong.albumId,
        duration: provisionalSong.duration > 0
            ? provisionalSong.duration
            : librarySong.duration,
        trackNumber: provisionalSong.trackNumber ?? librarySong.trackNumber,
      );
    }).toList();
  }

  /// Build SongModel objects from downloaded song metadata
  Future<List<SongModel>> _resolveSongsFromDownloads(
      List<String> songIds) async {
    final downloadedSongs = _buildDownloadedSongsMap();

    // Pre-fetch song durations from library to fill in missing values
    final librarySongs = await _loadLibrarySongsForMetadata();
    final libraryDurations = {for (var s in librarySongs) s.id: s.duration};

    return songIds.map((id) {
      if (downloadedSongs.containsKey(id)) {
        return downloadedSongs[id]!;
      } else {
        final albumId = _playlist?.songAlbumIds[id];
        final cachedTitle = _playlist?.songTitles[id];
        final title = (cachedTitle != null && cachedTitle.isNotEmpty)
            ? cachedTitle
            : 'Missing from library';
        final artist = _playlist?.songArtists[id] ?? 'Unknown Artist';
        var duration = _playlist?.songDurations[id] ?? 0;
        // Fallback to library duration if playlist duration is 0 or missing
        if (duration == 0 && libraryDurations.containsKey(id)) {
          duration = libraryDurations[id]!;
        }
        return SongModel(
          id: id,
          title: title,
          artist: artist,
          albumId: albumId,
          duration: duration,
          trackNumber: null,
        );
      }
    }).toList();
  }

  /// Playlist songs that can actually be downloaded: already downloaded or
  /// present in the library. Playlists can hold stale ids for songs that no
  /// longer exist on the server; those can never download, so they mirror the
  /// Downloads screen's "matched songs" rule and don't count against the
  /// fully-downloaded state. Falls back to all songs while the library list
  /// is still unknown.
  List<SongModel> get _matchedSongs {
    final librarySongs = _libraryController.state.songs;
    if (librarySongs.isEmpty) return _songs;
    final libraryIds = {for (final song in librarySongs) song.id};
    return _songs
        .where((s) =>
            _downloadedSongIds.contains(s.id) || libraryIds.contains(s.id))
        .toList();
  }

  bool get _isPlaylistFullyDownloaded {
    final matched = _matchedSongs;
    return matched.isNotEmpty &&
        matched.every((s) => _downloadedSongIds.contains(s.id));
  }

  bool get _isOfflineCopy =>
      _offlineCopyService.isRetainedPlaylist(widget.playlistId);

  bool get _shouldUseOfflineTracks =>
      _offlineService.isOffline || _isOfflineCopy;
}
