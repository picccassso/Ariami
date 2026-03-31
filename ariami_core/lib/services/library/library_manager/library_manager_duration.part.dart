part of '../library_manager.dart';

extension _LibraryManagerDurationPart on LibraryManager {
  void _ensureDurationWarmupImpl() {
    if (_library == null) return;
    if (_durationsReady || _durationWarmupRunning) return;
    unawaited(_startDurationWarmup());
  }

  Future<void> _startDurationWarmup() async {
    if (_library == null || _durationWarmupRunning) return;

    _durationWarmupRunning = true;
    _durationsReady = false;

    int pending = 0;
    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (_songNeedsDuration(song)) {
          pending++;
        }
      }
    }
    for (final song in _library!.standaloneSongs) {
      if (_songNeedsDuration(song)) {
        pending++;
      }
    }

    if (pending == 0) {
      _durationWarmupRunning = false;
      _durationsReady = true;
      _notifyDurationsReady();
      return;
    }

    print('[LibraryManager] Warming up durations for $pending songs...');
    int processed = 0;

    for (final album in _library!.albums.values) {
      for (var i = 0; i < album.songs.length; i++) {
        final song = album.songs[i];
        final songId = this._generateSongId(song.filePath);

        final cached = _durationCache[songId];
        if (cached != null &&
            cached > 0 &&
            (song.duration == null || song.duration == 0)) {
          final updated = song.copyWith(duration: cached);
          album.songs[i] = updated;
          await _persistDuration(updated, cached);
          continue;
        }

        if (!_songNeedsDuration(song)) {
          continue;
        }

        final duration =
            await _metadataExtractor.extractDuration(song.filePath);
        _durationCache[songId] = duration;

        if (duration != null && duration > 0) {
          final updated = song.copyWith(duration: duration);
          album.songs[i] = updated;
          await _persistDuration(updated, duration);
        }

        processed++;
        if (processed % 50 == 0) {
          print(
              '[LibraryManager] Duration warm-up progress: $processed/$pending');
        }
      }
    }

    for (var i = 0; i < _library!.standaloneSongs.length; i++) {
      final song = _library!.standaloneSongs[i];
      final songId = this._generateSongId(song.filePath);

      final cached = _durationCache[songId];
      if (cached != null &&
          cached > 0 &&
          (song.duration == null || song.duration == 0)) {
        final updated = song.copyWith(duration: cached);
        _library!.standaloneSongs[i] = updated;
        await _persistDuration(updated, cached);
        continue;
      }

      if (!_songNeedsDuration(song)) {
        continue;
      }

      final duration = await _metadataExtractor.extractDuration(song.filePath);
      _durationCache[songId] = duration;

      if (duration != null && duration > 0) {
        final updated = song.copyWith(duration: duration);
        _library!.standaloneSongs[i] = updated;
        await _persistDuration(updated, duration);
      }

      processed++;
      if (processed % 50 == 0) {
        print(
            '[LibraryManager] Duration warm-up progress: $processed/$pending');
      }
    }

    await _metadataCache?.save();

    _durationWarmupRunning = false;
    _durationsReady = true;
    print('[LibraryManager] Duration warm-up complete');
    _notifyDurationsReady();
  }

  bool _songNeedsDuration(SongMetadata song) {
    if (song.duration != null && song.duration! > 0) return false;
    final songId = this._generateSongId(song.filePath);
    final cached = _durationCache[songId];
    return cached == null || cached == 0;
  }

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
    if (_library == null) return null;

    // Search in all albums
    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (this._generateSongId(song.filePath) == songId) {
          return song.filePath;
        }
      }
    }

    // Search in standalone songs
    for (final song in _library!.standaloneSongs) {
      if (this._generateSongId(song.filePath) == songId) {
        return song.filePath;
      }
    }

    return null;
  }

  String? _getSongAlbumIdImpl(String songId) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (this._generateSongId(song.filePath) == songId) {
          return album.id;
        }
      }
    }

    return null;
  }

  Future<List<int>?> _getAlbumArtworkImpl(String albumId) async {
    if (_library == null) {
      return null;
    }

    final album = _library!.albums[albumId];
    if (album == null) {
      return null;
    }

    final source = await this._extractAlbumArtworkSource(album);
    return source?.artworkBytes;
  }

  Future<int?> _getSongDurationImpl(String songId) async {
    // Check cache first
    if (_durationCache.containsKey(songId)) {
      return _durationCache[songId];
    }

    // Check library metadata
    final existingMetadata = _findSongMetadataById(songId);
    if (existingMetadata?.duration != null && existingMetadata!.duration! > 0) {
      _durationCache[songId] = existingMetadata.duration;
      return existingMetadata.duration;
    }

    // Find the song file path
    final filePath = existingMetadata?.filePath ?? getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    // Extract duration
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

  SongMetadata? _findSongMetadataById(String songId) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (final song in album.songs) {
        if (this._generateSongId(song.filePath) == songId) {
          return song;
        }
      }
    }

    for (final song in _library!.standaloneSongs) {
      if (this._generateSongId(song.filePath) == songId) {
        return song;
      }
    }

    return null;
  }

  SongMetadata? _updateSongDurationById(String songId, int duration) {
    if (_library == null) return null;

    for (final album in _library!.albums.values) {
      for (var i = 0; i < album.songs.length; i++) {
        final song = album.songs[i];
        if (this._generateSongId(song.filePath) == songId) {
          final updated = song.copyWith(duration: duration);
          album.songs[i] = updated;
          return updated;
        }
      }
    }

    for (var i = 0; i < _library!.standaloneSongs.length; i++) {
      final song = _library!.standaloneSongs[i];
      if (this._generateSongId(song.filePath) == songId) {
        final updated = song.copyWith(duration: duration);
        _library!.standaloneSongs[i] = updated;
        return updated;
      }
    }

    return null;
  }

  Future<List<int>?> _getSongArtworkImpl(String songId) async {
    // Check cache first
    if (_songArtworkCache.containsKey(songId)) {
      return _songArtworkCache[songId];
    }

    // Find the song file path
    final filePath = getSongFilePath(songId);
    if (filePath == null) {
      return null;
    }

    // Extract artwork from the song file
    final artwork = await _metadataExtractor.extractArtwork(filePath);

    // Cache and return (including null to avoid repeated extraction attempts)
    _songArtworkCache[songId] = artwork;
    return artwork;
  }
}
