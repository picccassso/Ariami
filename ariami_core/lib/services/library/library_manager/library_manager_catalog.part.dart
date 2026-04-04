part of '../library_manager.dart';

extension _LibraryManagerCatalogPart on LibraryManager {
  Future<void> _clearMetadataCacheImpl() async {
    if (_metadataCache != null) {
      await _metadataCache!.clear();
      print('[LibraryManager] Metadata cache cleared');
    }
  }

  Future<void> _writeCatalogSnapshot() async {
    final library = _library;
    final catalogWriter = _catalogWriter;
    if (library == null || catalogWriter == null) {
      return;
    }

    try {
      final result = catalogWriter.writeFullSnapshot(
        library: library,
        songIdForPath: _generateSongId,
      );
      _latestCatalogToken = result.latestToken;
      print('[LibraryManager] Catalog snapshot write complete '
          '(albums: +${result.upsertedAlbumCount}/-${result.deletedAlbumCount}, '
          'songs: +${result.upsertedSongCount}/-${result.deletedSongCount}, '
          'playlists: +${result.upsertedPlaylistCount}/-${result.deletedPlaylistCount}, '
          'playlistSongs: +${result.upsertedPlaylistSongCount}/-${result.deletedPlaylistSongCount}, '
          'latestToken: ${result.latestToken})');

      await _precomputeAndPersistArtworkVariantsForAlbums(
        library: library,
        albumIds: library.albums.values.where((album) => album.isValid).map(
              (album) => album.id,
            ),
      );
    } catch (e, stackTrace) {
      print('[LibraryManager] WARNING: Failed to write catalog snapshot: $e');
      print('[LibraryManager] Catalog snapshot stack trace: $stackTrace');
    }
  }

  Future<void> _writeCatalogBatchForChanges({
    required LibraryUpdate update,
    required LibraryStructure previousLibrary,
    required LibraryStructure updatedLibrary,
  }) async {
    final catalogDatabase = _catalogDatabase;
    if (catalogDatabase == null) {
      return;
    }

    final database = catalogDatabase.database;
    final repository = CatalogRepository(database: database);
    final songRecordsById = _buildCatalogSongRecordsById(updatedLibrary);
    final albumRecordsById = _buildCatalogAlbumRecordsById(updatedLibrary);
    final playlistRecordsById =
        _buildCatalogPlaylistRecordsById(updatedLibrary);
    final previousPlaylistRecordsById =
        _buildCatalogPlaylistRecordsById(previousLibrary);
    final playlistSongPositions =
        _buildCatalogPlaylistSongPositions(updatedLibrary);
    final previousPlaylistSongPositions =
        _buildCatalogPlaylistSongPositions(previousLibrary);
    final previousSongAlbumIds = _buildSongAlbumIdIndex(previousLibrary);
    final updatedSongAlbumIds = _buildSongAlbumIdIndex(updatedLibrary);

    final upsertSongIds = <String>{
      ...update.addedSongIds,
      ...update.modifiedSongIds,
    }..removeWhere((songId) => !songRecordsById.containsKey(songId));
    final deletedSongIds = <String>{...update.removedSongIds};

    final affectedAlbumIds = <String>{...update.affectedAlbumIds};
    for (final songId in upsertSongIds) {
      final previousAlbumId = previousSongAlbumIds[songId];
      final updatedAlbumId = updatedSongAlbumIds[songId];
      if (previousAlbumId != null) {
        affectedAlbumIds.add(previousAlbumId);
      }
      if (updatedAlbumId != null) {
        affectedAlbumIds.add(updatedAlbumId);
      }
    }
    for (final songId in deletedSongIds) {
      final previousAlbumId = previousSongAlbumIds[songId];
      if (previousAlbumId != null) {
        affectedAlbumIds.add(previousAlbumId);
      }
    }

    final orderedUpsertSongIds = upsertSongIds.toList()..sort();
    final orderedDeletedSongIds = deletedSongIds.toList()..sort();
    final orderedAffectedAlbumIds = affectedAlbumIds.toList()..sort();
    final upsertPlaylistIds = playlistRecordsById.entries
        .where(
          (entry) => _playlistRecordChanged(
            previousPlaylistRecordsById[entry.key],
            entry.value,
          ),
        )
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final deletedPlaylistIds = previousPlaylistRecordsById.keys
        .where((playlistId) => !playlistRecordsById.containsKey(playlistId))
        .toList()
      ..sort();
    final deletedPlaylistIdSet = deletedPlaylistIds.toSet();
    final upsertPlaylistSongKeys = playlistSongPositions.entries
        .where(
          (entry) => previousPlaylistSongPositions[entry.key] != entry.value,
        )
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final deletedPlaylistSongKeys = previousPlaylistSongPositions.keys
        .where(
          (key) =>
              !playlistSongPositions.containsKey(key) &&
              !deletedPlaylistIdSet.contains(key.playlistId),
        )
        .toList()
      ..sort();

    var tokenCursor = _readLatestTokenFromDatabase(database);
    final occurredEpochMs = DateTime.now().millisecondsSinceEpoch;

    database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final songId in orderedUpsertSongIds) {
        tokenCursor += 1;
        final record = songRecordsById[songId]!;
        repository.upsertSong(
          CatalogSongRecord(
            id: record.id,
            filePath: record.filePath,
            title: record.title,
            artist: record.artist,
            albumId: record.albumId,
            durationSeconds: record.durationSeconds,
            trackNumber: record.trackNumber,
            fileSizeBytes: record.fileSizeBytes,
            modifiedEpochMs: record.modifiedEpochMs,
            artworkKey: record.artworkKey,
            updatedToken: tokenCursor,
            isDeleted: false,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'song',
          entityId: songId,
          op: 'upsert',
          payloadJson: _catalogSongPayloadJson(record),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in orderedDeletedSongIds) {
        tokenCursor += 1;
        repository.softDeleteSong(songId, tokenCursor);
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'song',
          entityId: songId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final albumId in orderedAffectedAlbumIds) {
        tokenCursor += 1;
        final record = albumRecordsById[albumId];
        if (record != null) {
          repository.upsertAlbum(
            CatalogAlbumRecord(
              id: record.id,
              title: record.title,
              artist: record.artist,
              year: record.year,
              coverArtKey: record.coverArtKey,
              songCount: record.songCount,
              durationSeconds: record.durationSeconds,
              updatedToken: tokenCursor,
              isDeleted: false,
            ),
          );
          _insertLibraryChangeEvent(
            database: database,
            entityType: 'album',
            entityId: albumId,
            op: 'upsert',
            payloadJson: _catalogAlbumPayloadJson(record),
            occurredEpochMs: occurredEpochMs,
          );
        } else {
          repository.softDeleteAlbum(albumId, tokenCursor);
          _insertLibraryChangeEvent(
            database: database,
            entityType: 'album',
            entityId: albumId,
            op: 'delete',
            occurredEpochMs: occurredEpochMs,
          );
        }
      }

      for (final playlistId in upsertPlaylistIds) {
        tokenCursor += 1;
        final record = playlistRecordsById[playlistId]!;
        repository.upsertPlaylist(
          CatalogPlaylistRecord(
            id: record.id,
            name: record.name,
            songCount: record.songCount,
            durationSeconds: record.durationSeconds,
            updatedToken: tokenCursor,
            isDeleted: false,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'playlist',
          entityId: playlistId,
          op: 'upsert',
          payloadJson: _catalogPlaylistPayloadJson(
            record,
            updatedLibrary: updatedLibrary,
          ),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final key in upsertPlaylistSongKeys) {
        tokenCursor += 1;
        final position = playlistSongPositions[key]!;
        repository.upsertPlaylistSong(
          CatalogPlaylistSongRecord(
            playlistId: key.playlistId,
            songId: key.songId,
            position: position,
            updatedToken: tokenCursor,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'playlist_song',
          entityId: key.entityId,
          op: 'upsert',
          payloadJson: _catalogPlaylistSongPayloadJson(
            key: key,
            position: position,
          ),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final key in deletedPlaylistSongKeys) {
        tokenCursor += 1;
        repository.deletePlaylistSong(key.playlistId, key.position);
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'playlist_song',
          entityId: key.entityId,
          op: 'delete',
          payloadJson: _catalogPlaylistSongDeletePayloadJson(key),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final playlistId in deletedPlaylistIds) {
        tokenCursor += 1;
        repository.softDeletePlaylist(playlistId, tokenCursor);
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'playlist',
          entityId: playlistId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      database.execute('COMMIT;');
      _latestCatalogToken = tokenCursor;
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }

    await _precomputeAndPersistArtworkVariantsForAlbums(
      library: updatedLibrary,
      albumIds: orderedAffectedAlbumIds,
    );
  }

  Future<void> _writeCatalogDurationUpdates(Set<String> updatedSongIds) async {
    final catalogDatabase = _catalogDatabase;
    final library = _library;
    if (catalogDatabase == null || library == null || updatedSongIds.isEmpty) {
      return;
    }

    final database = catalogDatabase.database;
    final repository = CatalogRepository(database: database);
    final songRecordsById = _buildCatalogSongRecordsById(library);
    final albumRecordsById = _buildCatalogAlbumRecordsById(library);
    final playlistRecordsById = _buildCatalogPlaylistRecordsById(library);
    final songAlbumIds = _buildSongAlbumIdIndex(library);
    final affectedPlaylistIds = library.folderPlaylists
        .where(
          (playlist) => playlist.songIds.any(updatedSongIds.contains),
        )
        .map((playlist) => playlist.id)
        .toSet()
        .toList()
      ..sort();
    final affectedAlbumIds = updatedSongIds
        .map((songId) => songAlbumIds[songId])
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final orderedSongIds = updatedSongIds.toList()..sort();

    var tokenCursor = _readLatestTokenFromDatabase(database);
    final occurredEpochMs = DateTime.now().millisecondsSinceEpoch;

    database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final songId in orderedSongIds) {
        final record = songRecordsById[songId];
        if (record == null) {
          continue;
        }
        tokenCursor += 1;
        repository.upsertSong(
          CatalogSongRecord(
            id: record.id,
            filePath: record.filePath,
            title: record.title,
            artist: record.artist,
            albumId: record.albumId,
            durationSeconds: record.durationSeconds,
            trackNumber: record.trackNumber,
            fileSizeBytes: record.fileSizeBytes,
            modifiedEpochMs: record.modifiedEpochMs,
            artworkKey: record.artworkKey,
            updatedToken: tokenCursor,
            isDeleted: false,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'song',
          entityId: songId,
          op: 'upsert',
          payloadJson: _catalogSongPayloadJson(record),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final albumId in affectedAlbumIds) {
        final record = albumRecordsById[albumId];
        if (record == null) {
          continue;
        }
        tokenCursor += 1;
        repository.upsertAlbum(
          CatalogAlbumRecord(
            id: record.id,
            title: record.title,
            artist: record.artist,
            year: record.year,
            coverArtKey: record.coverArtKey,
            songCount: record.songCount,
            durationSeconds: record.durationSeconds,
            updatedToken: tokenCursor,
            isDeleted: false,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'album',
          entityId: albumId,
          op: 'upsert',
          payloadJson: _catalogAlbumPayloadJson(record),
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final playlistId in affectedPlaylistIds) {
        final record = playlistRecordsById[playlistId];
        if (record == null) {
          continue;
        }
        tokenCursor += 1;
        repository.upsertPlaylist(
          CatalogPlaylistRecord(
            id: record.id,
            name: record.name,
            songCount: record.songCount,
            durationSeconds: record.durationSeconds,
            updatedToken: tokenCursor,
            isDeleted: false,
          ),
        );
        _insertLibraryChangeEvent(
          database: database,
          entityType: 'playlist',
          entityId: playlistId,
          op: 'upsert',
          payloadJson: _catalogPlaylistPayloadJson(
            record,
            updatedLibrary: library,
          ),
          occurredEpochMs: occurredEpochMs,
        );
      }

      database.execute('COMMIT;');
      _latestCatalogToken = tokenCursor;
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> _precomputeAndPersistArtworkVariantsForAlbums({
    required LibraryStructure library,
    required Iterable<String> albumIds,
  }) async {
    final catalogWriter = _catalogWriter;
    final artworkService = _artworkPrecomputeService;
    if (catalogWriter == null || artworkService == null) {
      return;
    }

    final orderedAlbumIds = albumIds.toSet().toList()..sort();
    for (final albumId in orderedAlbumIds) {
      final album = library.albums[albumId];
      if (album == null || !album.isValid) {
        continue;
      }

      try {
        final source = await _extractAlbumArtworkSource(album);
        if (source == null) {
          continue;
        }

        final fullEtag = _computeArtworkEtag(source.artworkBytes);
        final fullMimeType = _detectArtworkMimeType(source.artworkBytes);
        catalogWriter.upsertArtworkVariant(
          CatalogArtworkVariantRecord(
            artworkKey: album.id,
            variant: 'full',
            mimeType: fullMimeType,
            byteSize: source.artworkBytes.length,
            etag: fullEtag,
            lastModifiedEpochMs: source.lastModifiedEpochMs,
            storagePath: source.referencePath,
            updatedToken: _latestCatalogToken,
          ),
        );

        final thumbnailBytes = await artworkService.precomputeArtworkVariant(
          album.id,
          source.artworkBytes,
          ArtworkSize.thumbnail,
        );
        final expectedThumbnailPath = artworkService.getVariantStoragePath(
          album.id,
          ArtworkSize.thumbnail,
          originalReferencePath: source.referencePath,
        );
        final thumbnailFile = File(expectedThumbnailPath);
        final thumbnailExists = await thumbnailFile.exists();
        final thumbnailStoragePath =
            thumbnailExists ? thumbnailFile.path : source.referencePath;
        final thumbnailLastModified = thumbnailExists
            ? (await thumbnailFile.stat()).modified.millisecondsSinceEpoch
            : source.lastModifiedEpochMs;
        catalogWriter.upsertArtworkVariant(
          CatalogArtworkVariantRecord(
            artworkKey: album.id,
            variant: 'thumb_200',
            mimeType: _detectArtworkMimeType(thumbnailBytes),
            byteSize: thumbnailBytes.length,
            etag: _computeArtworkEtag(thumbnailBytes),
            lastModifiedEpochMs: thumbnailLastModified,
            storagePath: thumbnailStoragePath,
            updatedToken: _latestCatalogToken,
          ),
        );
      } catch (e) {
        print('[LibraryManager] WARNING: Failed artwork precompute for '
            'album $albumId: $e');
      }
    }
  }

  Future<_AlbumArtworkSource?> _extractAlbumArtworkSource(Album album) async {
    if (_artworkCache.containsKey(album.id)) {
      final cachedArtwork = _artworkCache[album.id];
      if (cachedArtwork == null) {
        return null;
      }

      final sourceSong = album.songs.isNotEmpty ? album.songs.first : null;
      if (sourceSong == null) {
        return null;
      }

      return _AlbumArtworkSource(
        artworkBytes: cachedArtwork,
        referencePath: sourceSong.filePath,
        lastModifiedEpochMs: sourceSong.modifiedTime?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
      );
    }

    for (final song in album.songs) {
      final artwork = await _metadataExtractor.extractArtwork(song.filePath);
      if (artwork != null) {
        _artworkCache[album.id] = artwork;
        return _AlbumArtworkSource(
          artworkBytes: artwork,
          referencePath: song.filePath,
          lastModifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    _artworkCache[album.id] = null;
    return null;
  }

  String _computeArtworkEtag(List<int> artworkBytes) {
    return md5.convert(artworkBytes).toString();
  }

  String _detectArtworkMimeType(List<int> artworkBytes) {
    if (artworkBytes.length >= 3 &&
        artworkBytes[0] == 0xFF &&
        artworkBytes[1] == 0xD8 &&
        artworkBytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (artworkBytes.length >= 8 &&
        artworkBytes[0] == 0x89 &&
        artworkBytes[1] == 0x50 &&
        artworkBytes[2] == 0x4E &&
        artworkBytes[3] == 0x47 &&
        artworkBytes[4] == 0x0D &&
        artworkBytes[5] == 0x0A &&
        artworkBytes[6] == 0x1A &&
        artworkBytes[7] == 0x0A) {
      return 'image/png';
    }

    if (artworkBytes.length >= 6 &&
        artworkBytes[0] == 0x47 &&
        artworkBytes[1] == 0x49 &&
        artworkBytes[2] == 0x46 &&
        artworkBytes[3] == 0x38 &&
        (artworkBytes[4] == 0x37 || artworkBytes[4] == 0x39) &&
        artworkBytes[5] == 0x61) {
      return 'image/gif';
    }

    if (artworkBytes.length >= 12 &&
        artworkBytes[0] == 0x52 &&
        artworkBytes[1] == 0x49 &&
        artworkBytes[2] == 0x46 &&
        artworkBytes[3] == 0x46 &&
        artworkBytes[8] == 0x57 &&
        artworkBytes[9] == 0x45 &&
        artworkBytes[10] == 0x42 &&
        artworkBytes[11] == 0x50) {
      return 'image/webp';
    }

    return 'image/jpeg';
  }

  Map<String, CatalogSongRecord> _buildCatalogSongRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogSongRecord>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        records[songId] = CatalogSongRecord(
          id: songId,
          filePath: song.filePath,
          title: song.title ?? _getFilenameWithoutExtension(song.filePath),
          artist: song.artist ?? 'Unknown Artist',
          albumId: album.id,
          durationSeconds: song.duration ?? 0,
          trackNumber: song.trackNumber,
          fileSizeBytes: song.fileSize,
          modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
          artworkKey: album.id,
          updatedToken: 0,
          isDeleted: false,
        );
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      records[songId] = CatalogSongRecord(
        id: songId,
        filePath: song.filePath,
        title: song.title ?? _getFilenameWithoutExtension(song.filePath),
        artist: song.artist ?? 'Unknown Artist',
        albumId: null,
        durationSeconds: song.duration ?? 0,
        trackNumber: song.trackNumber,
        fileSizeBytes: song.fileSize,
        modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
        artworkKey: null,
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<String, CatalogAlbumRecord> _buildCatalogAlbumRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogAlbumRecord>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      var durationSeconds = 0;
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationSeconds += duration;
        }
      }

      records[album.id] = CatalogAlbumRecord(
        id: album.id,
        title: album.title,
        artist: album.artist,
        year: album.year,
        coverArtKey: album.artworkPath != null ? album.id : null,
        songCount: album.songCount,
        durationSeconds: durationSeconds,
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<String, CatalogPlaylistRecord> _buildCatalogPlaylistRecordsById(
    LibraryStructure library,
  ) {
    final records = <String, CatalogPlaylistRecord>{};
    final songDurationsById = _buildSongDurationsById(library);

    for (final playlist in library.folderPlaylists) {
      records[playlist.id] = CatalogPlaylistRecord(
        id: playlist.id,
        name: playlist.name,
        songCount: playlist.songCount,
        durationSeconds:
            _playlistDurationSeconds(playlist.songIds, songDurationsById),
        updatedToken: 0,
        isDeleted: false,
      );
    }

    return records;
  }

  Map<_CatalogPlaylistSongKey, int> _buildCatalogPlaylistSongPositions(
    LibraryStructure library,
  ) {
    final positions = <_CatalogPlaylistSongKey, int>{};

    for (final playlist in library.folderPlaylists) {
      for (var index = 0; index < playlist.songIds.length; index++) {
        positions[_CatalogPlaylistSongKey(
          playlistId: playlist.id,
          songId: playlist.songIds[index],
          position: index,
        )] = index;
      }
    }

    return positions;
  }

  Map<String, String?> _buildSongAlbumIdIndex(LibraryStructure library) {
    final index = <String, String?>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = _generateSongId(song.filePath);
        index[songId] = album.id;
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = _generateSongId(song.filePath);
      index[songId] = null;
    }

    return index;
  }

  Map<String, int> _buildSongDurationsById(LibraryStructure library) {
    final durationsById = <String, int>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationsById[_generateSongId(song.filePath)] = duration;
        }
      }
    }

    for (final song in library.standaloneSongs) {
      final duration = song.duration;
      if (duration != null && duration > 0) {
        durationsById[_generateSongId(song.filePath)] = duration;
      }
    }

    return durationsById;
  }

  int _playlistDurationSeconds(
    List<String> songIds,
    Map<String, int> songDurationsById,
  ) {
    var totalDurationSeconds = 0;
    for (final songId in songIds) {
      totalDurationSeconds += songDurationsById[songId] ?? 0;
    }
    return totalDurationSeconds;
  }

  int _readLatestTokenFromDatabase(Database database) {
    final rows = database.select(
      '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
    );
    return rows.first['latest_token'] as int;
  }

  void _insertLibraryChangeEvent({
    required Database database,
    required String entityType,
    required String entityId,
    required String op,
    String? payloadJson,
    required int occurredEpochMs,
  }) {
    database.execute(
      '''
INSERT INTO library_changes (
  entity_type,
  entity_id,
  op,
  payload_json,
  occurred_epoch_ms,
  actor_user_id
) VALUES (?, ?, ?, ?, ?, NULL);
''',
      <Object?>[
        entityType,
        entityId,
        op,
        payloadJson,
        occurredEpochMs,
      ],
    );
  }

  bool _playlistRecordChanged(
    CatalogPlaylistRecord? previous,
    CatalogPlaylistRecord current,
  ) {
    if (previous == null) {
      return true;
    }

    return previous.name != current.name ||
        previous.songCount != current.songCount ||
        previous.durationSeconds != current.durationSeconds;
  }

  String _catalogAlbumPayloadJson(CatalogAlbumRecord record) {
    return jsonEncode(<String, dynamic>{
      'id': record.id,
      'title': record.title,
      'artist': record.artist,
      'coverArt': record.coverArtKey == null
          ? null
          : '/api/artwork/${Uri.encodeComponent(record.id)}',
      'songCount': record.songCount,
      'duration': record.durationSeconds,
    });
  }

  String _catalogSongPayloadJson(CatalogSongRecord record) {
    return jsonEncode(<String, dynamic>{
      'id': record.id,
      'title': record.title,
      'artist': record.artist,
      'albumId': record.albumId,
      'duration': record.durationSeconds,
      'trackNumber': record.trackNumber,
    });
  }

  String _catalogPlaylistPayloadJson(
    CatalogPlaylistRecord record, {
    required LibraryStructure updatedLibrary,
  }) {
    final playlist =
        updatedLibrary.folderPlaylists.where((p) => p.id == record.id).first;
    return jsonEncode(<String, dynamic>{
      'id': record.id,
      'name': record.name,
      'songCount': record.songCount,
      'duration': record.durationSeconds,
      'songIds': playlist.songIds,
    });
  }

  String _catalogPlaylistSongPayloadJson({
    required _CatalogPlaylistSongKey key,
    required int position,
  }) {
    return jsonEncode(<String, dynamic>{
      'playlistId': key.playlistId,
      'songId': key.songId,
      'position': position,
    });
  }

  String _catalogPlaylistSongDeletePayloadJson(_CatalogPlaylistSongKey key) {
    return jsonEncode(<String, dynamic>{
      'playlistId': key.playlistId,
      'songId': key.songId,
      'position': key.position,
    });
  }
}

class _AlbumArtworkSource {
  _AlbumArtworkSource({
    required this.artworkBytes,
    required this.referencePath,
    required this.lastModifiedEpochMs,
  });

  final List<int> artworkBytes;
  final String referencePath;
  final int lastModifiedEpochMs;
}

class _CatalogPlaylistSongKey implements Comparable<_CatalogPlaylistSongKey> {
  const _CatalogPlaylistSongKey({
    required this.playlistId,
    required this.songId,
    required this.position,
  });

  final String playlistId;
  final String songId;
  final int position;

  String get entityId => '$playlistId:$position';

  @override
  int compareTo(_CatalogPlaylistSongKey other) {
    final playlistCompare = playlistId.compareTo(other.playlistId);
    if (playlistCompare != 0) {
      return playlistCompare;
    }
    final positionCompare = position.compareTo(other.position);
    if (positionCompare != 0) {
      return positionCompare;
    }
    return songId.compareTo(other.songId);
  }

  @override
  bool operator ==(Object other) {
    return other is _CatalogPlaylistSongKey &&
        other.playlistId == playlistId &&
        other.songId == songId &&
        other.position == position;
  }

  @override
  int get hashCode => Object.hash(playlistId, songId, position);
}
