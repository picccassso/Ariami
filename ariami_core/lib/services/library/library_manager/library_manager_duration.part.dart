part of '../library_manager.dart';

extension _LibraryManagerDurationPart on LibraryManager {
  Future<void> _persistDuration(
    SongMetadata song,
    int duration, {
    bool saveNow = false,
  }) async {
    if (_metadataCache == null) return;
    final updated = song.copyWith(duration: duration);
    final mtime = song.modifiedTime?.millisecondsSinceEpoch;
    final size = song.fileSize;
    await _metadataCache!.upsert(
      song.filePath,
      updated,
      mtime: mtime,
      size: size,
    );
    if (saveNow) {
      await _metadataCache!.save();
    }
  }

  String? _getSongFilePathImpl(String songId) {
    if (_library != null && _songPathById.isEmpty) {
      _rebuildSongIndexes();
    }
    return _songPathById[songId] ?? _getCatalogSongById(songId)?.filePath;
  }

  String? _getSongAlbumIdImpl(String songId) {
    if (_library == null) return null;
    if (_songById.isEmpty) {
      _rebuildSongIndexes();
    }
    return _songAlbumIdById[songId];
  }

  Future<List<int>?> _getAlbumArtworkImpl(String albumId) async {
    if (_library == null) {
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      return null;
    }

    final source = await _extractAlbumArtworkSource(album);
    return source?.artworkBytes;
  }

  Future<int?> _getSongDurationImpl(String songId) async {
    if (_durationCache.containsKey(songId)) {
      return _durationCache[songId];
    }

    final existingMetadata = _findSongMetadataById(songId);
    if (existingMetadata?.duration != null && existingMetadata!.duration! > 0) {
      _durationCache[songId] = existingMetadata.duration;
      return existingMetadata.duration;
    }

    final filePath = existingMetadata?.filePath ?? getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    final duration = await _metadataExtractor.extractDuration(filePath);
    _durationCache[songId] = duration;

    if (duration != null && duration > 0) {
      final updatedMetadata = _updateSongDurationById(songId, duration);
      if (updatedMetadata != null) {
        await _persistDuration(updatedMetadata, duration, saveNow: true);
      }
    }

    return duration;
  }

  int? _getKnownSongDurationImpl(String songId) {
    if (_durationCache.containsKey(songId)) {
      return _durationCache[songId];
    }

    final existingMetadata = _findSongMetadataById(songId);
    if (existingMetadata?.duration != null && existingMetadata!.duration! > 0) {
      _durationCache[songId] = existingMetadata.duration;
      return existingMetadata.duration;
    }

    final catalogDuration = _getCatalogSongById(songId)?.durationSeconds;
    if (catalogDuration != null && catalogDuration > 0) {
      _durationCache[songId] = catalogDuration;
      return catalogDuration;
    }

    return null;
  }

  int? _getKnownSongBitrateImpl(String songId) {
    final bitrate = _findSongMetadataById(songId)?.bitrate;
    if (bitrate != null && bitrate > 0) return bitrate;
    final catalogBitrate = _getCatalogSongById(songId)?.bitrateKbps;
    return catalogBitrate != null && catalogBitrate > 0 ? catalogBitrate : null;
  }

  CatalogSongRecord? _getCatalogSongById(String songId) {
    try {
      return createCatalogRepository()?.getSongById(songId);
    } catch (_) {
      return null;
    }
  }

  SongMetadata? _findSongMetadataById(String songId) {
    if (_library == null) return null;
    if (_songById.isEmpty) {
      _rebuildSongIndexes();
    }
    return _songById[songId];
  }

  SongMetadata? _updateSongDurationById(String songId, int duration) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (var i = 0; i < album.songs.length; i++) {
        final song = album.songs[i];
        if (_generateSongId(song.filePath) == songId) {
          final updated = song.copyWith(duration: duration);
          album.songs[i] = updated;
          _songById[songId] = updated;
          _songPathById[songId] = updated.filePath;
          _songAlbumIdById[songId] = album.id;
          return updated;
        }
      }
    }

    for (var i = 0; i < _library!.standaloneSongs.length; i++) {
      final song = _library!.standaloneSongs[i];
      if (_generateSongId(song.filePath) == songId) {
        final updated = song.copyWith(duration: duration);
        _library!.standaloneSongs[i] = updated;
        _songById[songId] = updated;
        _songPathById[songId] = updated.filePath;
        _songAlbumIdById[songId] = null;
        return updated;
      }
    }

    return null;
  }

  Future<List<int>?> _getSongArtworkImpl(String songId) async {
    if (_songArtworkCache.containsKey(songId)) {
      return _songArtworkCache[songId];
    }

    final filePath = getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    final artwork = await _metadataExtractor.extractArtwork(filePath);

    // Cache and return (including null to avoid repeated extraction attempts)
    _songArtworkCache[songId] = artwork;
    return artwork;
  }
}
