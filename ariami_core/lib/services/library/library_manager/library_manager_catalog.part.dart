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
        songIdForPath: this._generateSongId,
      );
      _latestCatalogToken = result.latestToken;
      print('[LibraryManager] Catalog snapshot write complete '
          '(albums: +${result.upsertedAlbumCount}/-${result.deletedAlbumCount}, '
          'songs: +${result.upsertedSongCount}/-${result.deletedSongCount}, '
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
        final songId = this._generateSongId(song.filePath);
        records[songId] = CatalogSongRecord(
          id: songId,
          filePath: song.filePath,
          title: song.title ?? this._getFilenameWithoutExtension(song.filePath),
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
      final songId = this._generateSongId(song.filePath);
      records[songId] = CatalogSongRecord(
        id: songId,
        filePath: song.filePath,
        title: song.title ?? this._getFilenameWithoutExtension(song.filePath),
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

  Map<String, String?> _buildSongAlbumIdIndex(LibraryStructure library) {
    final index = <String, String?>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final songId = this._generateSongId(song.filePath);
        index[songId] = album.id;
      }
    }

    for (final song in library.standaloneSongs) {
      final songId = this._generateSongId(song.filePath);
      index[songId] = null;
    }

    return index;
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
) VALUES (?, ?, ?, NULL, ?, NULL);
''',
      <Object?>[
        entityType,
        entityId,
        op,
        occurredEpochMs,
      ],
    );
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
