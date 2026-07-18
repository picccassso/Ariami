part of '../library_manager.dart';

extension _LibraryManagerCatalogPart on LibraryManager {
  Future<void> _writeCatalogSnapshot() async {
    if (!_shouldWriteCatalog) {
      return;
    }

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
    if (!_shouldWriteCatalog) {
      return;
    }

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
    for (final entry in updatedSongAlbumIds.entries) {
      final songId = entry.key;
      if (!songRecordsById.containsKey(songId)) {
        continue;
      }
      if (previousSongAlbumIds[songId] != entry.value) {
        upsertSongIds.add(songId);
      }
    }
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
            bitrateKbps: record.bitrateKbps,
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
}
