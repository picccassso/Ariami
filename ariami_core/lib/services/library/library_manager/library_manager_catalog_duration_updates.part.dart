part of '../library_manager.dart';

extension _LibraryManagerCatalogDurationUpdatesPart on LibraryManager {
  Future<void> _writeCatalogDurationUpdates(Set<String> updatedSongIds) async {
    if (!_shouldWriteCatalog) {
      return;
    }

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
}
