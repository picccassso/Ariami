part of '../library_manager.dart';

extension _LibraryManagerApiPart on LibraryManager {
  Map<String, dynamic> _toApiJsonImpl(String baseUrl) {
    if (_library == null) {
      return {
        'albums': [],
        'songs': [],
        'playlists': [],
        'durationsReady': _durationsReady,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }

    // Convert albums to API format
    final albumsJson = _library!.albums.values
        .where((album) => album.isValid) // Only valid albums (2+ songs)
        .map((album) => _albumToApiJson(album, baseUrl))
        .toList();

    // Convert ALL songs to API format (album songs + standalone songs)
    final songsJson = <Map<String, dynamic>>[];

    // Add songs from all valid albums
    for (final album in _library!.albums.values.where((a) => a.isValid)) {
      for (final song in album.sortedSongs) {
        songsJson.add(_songToApiJson(song, baseUrl, album.id));
      }
    }

    // Add standalone songs (not in any album)
    for (final song in _library!.standaloneSongs) {
      songsJson.add(_songToApiJson(song, baseUrl, null));
    }

    // Convert folder playlists to API format
    final playlistsJson =
        _library!.folderPlaylists.map((playlist) => playlist.toJson()).toList();

    return {
      'albums': albumsJson,
      'songs': songsJson,
      'playlists': playlistsJson,
      'durationsReady': _durationsReady,
      'lastUpdated':
          _lastScanTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _toApiJsonWithDurationsImpl(
      String baseUrl) async {
    if (_library == null) {
      return {
        'albums': [],
        'songs': [],
        'playlists': [],
        'durationsReady': _durationsReady,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }

    // Convert albums to API format (unchanged)
    final albumsJson = _library!.albums.values
        .where((album) => album.isValid) // Only valid albums (2+ songs)
        .map((album) => _albumToApiJson(album, baseUrl))
        .toList();

    // Convert ALL songs to API format with lazy duration extraction
    final songsJson = <Map<String, dynamic>>[];

    // Add songs from all valid albums
    for (final album in _library!.albums.values.where((a) => a.isValid)) {
      for (final song in album.sortedSongs) {
        songsJson.add(
          await _songToApiJsonWithDuration(song, baseUrl, album.id),
        );
      }
    }

    // Add standalone songs (not in any album)
    for (final song in _library!.standaloneSongs) {
      songsJson.add(
        await _songToApiJsonWithDuration(song, baseUrl, null),
      );
    }

    // Convert folder playlists to API format
    final playlistsJson =
        _library!.folderPlaylists.map((playlist) => playlist.toJson()).toList();

    return {
      'albums': albumsJson,
      'songs': songsJson,
      'playlists': playlistsJson,
      'durationsReady': _durationsReady,
      'lastUpdated':
          _lastScanTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Convert Album to API JSON format
  Map<String, dynamic> _albumToApiJson(Album album, String baseUrl) {
    int totalDurationSeconds = 0;
    for (final song in album.songs) {
      final songId = _generateSongId(song.filePath);
      totalDurationSeconds += _resolveSongDuration(song, songId);
    }

    return {
      'id': album.id,
      'title': album.title,
      'artist': album.artist,
      'coverArt':
          album.artworkPath != null ? '$baseUrl/api/artwork/${album.id}' : null,
      'songCount': album.songCount,
      'duration': totalDurationSeconds,
    };
  }

  /// Convert SongMetadata to API JSON format
  Map<String, dynamic> _songToApiJson(
      SongMetadata song, String baseUrl, String? albumId) {
    // Generate unique song ID from file path
    final songId = _generateSongId(song.filePath);
    final duration = _resolveSongDuration(song, songId);

    return {
      'id': songId,
      'title': song.title ?? _getFilenameWithoutExtension(song.filePath),
      'artist': song.artist ?? 'Unknown Artist',
      'albumId': albumId,
      'duration': duration,
      'trackNumber': song.trackNumber,
    };
  }

  int _resolveSongDuration(SongMetadata song, String songId) {
    final duration = song.duration;
    if (duration != null && duration > 0) return duration;

    final cached = _durationCache[songId];
    if (cached != null && cached > 0) return cached;

    return 0;
  }

  /// Generate a unique song ID from file path
  String _generateSongId(String filePath) {
    final bytes = utf8.encode(filePath);
    final hash = md5.convert(bytes);
    return hash.toString().substring(0, 12); // First 12 chars of hash
  }

  /// Extract filename without extension
  String _getFilenameWithoutExtension(String filePath) {
    return path.basenameWithoutExtension(filePath);
  }

  Future<Map<String, dynamic>?> _getAlbumDetailImpl(
      String albumId, String baseUrl) async {
    print('[LibraryManager] ========== GET ALBUM DETAIL ==========');
    print('[LibraryManager] Album ID: $albumId');
    print('[LibraryManager] Base URL: $baseUrl');

    if (_library == null) {
      print('[LibraryManager] ERROR: Library is null!');
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      print('[LibraryManager] ERROR: Album not found with ID: $albumId');
      print(
          '[LibraryManager] Available album IDs: ${_library!.albums.keys.toList()}');
      return null;
    }

    print('[LibraryManager] Found album: ${album.title} by ${album.artist}');
    print('[LibraryManager] Album artworkPath: ${album.artworkPath}');
    print('[LibraryManager] Album has artwork: ${album.artworkPath != null}');

    final coverArtUrl =
        album.artworkPath != null ? '$baseUrl/api/artwork/${album.id}' : null;
    print('[LibraryManager] Generated coverArt URL: $coverArtUrl');

    // Build songs with lazily extracted durations
    final songsJson = <Map<String, dynamic>>[];
    for (final song in album.sortedSongs) {
      final songJson = await _songToApiJsonWithDuration(song, baseUrl, albumId);
      songsJson.add(songJson);
    }

    print('[LibraryManager] Returning ${songsJson.length} songs');
    print('[LibraryManager] =======================================');

    return {
      'id': album.id,
      'title': album.title,
      'artist': album.artist,
      'year': album.year?.toString(),
      'coverArt': coverArtUrl,
      'songs': songsJson,
    };
  }

  /// Convert SongMetadata to API JSON format with lazy duration extraction
  Future<Map<String, dynamic>> _songToApiJsonWithDuration(
      SongMetadata song, String baseUrl, String? albumId) async {
    final songId = _generateSongId(song.filePath);

    // Use cached duration or extract lazily
    int duration = song.duration ?? 0;
    if (duration == 0) {
      final extractedDuration = await getSongDuration(songId);
      duration = extractedDuration ?? 0;
    }

    return {
      'id': songId,
      'title': song.title ?? _getFilenameWithoutExtension(song.filePath),
      'artist': song.artist ?? 'Unknown Artist',
      'albumId': albumId,
      'duration': duration,
      'trackNumber': song.trackNumber,
    };
  }
}
