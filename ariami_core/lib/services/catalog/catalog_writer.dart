import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/models/song_metadata.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

class CatalogWriteResult {
  CatalogWriteResult({
    required this.upsertedAlbumCount,
    required this.upsertedSongCount,
    required this.deletedAlbumCount,
    required this.deletedSongCount,
    required this.latestToken,
  });

  final int upsertedAlbumCount;
  final int upsertedSongCount;
  final int deletedAlbumCount;
  final int deletedSongCount;
  final int latestToken;
}

class CatalogArtworkVariantRecord {
  CatalogArtworkVariantRecord({
    required this.artworkKey,
    required this.variant,
    required this.mimeType,
    required this.byteSize,
    required this.etag,
    required this.lastModifiedEpochMs,
    required this.storagePath,
    required this.updatedToken,
  });

  final String artworkKey;
  final String variant;
  final String mimeType;
  final int byteSize;
  final String etag;
  final int lastModifiedEpochMs;
  final String storagePath;
  final int updatedToken;
}

/// Writes scanner output into catalog rows and library change events.
class CatalogWriter {
  CatalogWriter({required Database database})
      : _database = database,
        _repository = CatalogRepository(database: database) {
    _latestToken = _repository.getLatestToken();
  }

  final Database _database;
  final CatalogRepository _repository;
  late int _latestToken;

  int get latestToken => _latestToken;

  void upsertArtworkVariant(CatalogArtworkVariantRecord record) {
    _database.execute(
      '''
INSERT INTO artwork_variants (
  artwork_key,
  variant,
  mime_type,
  byte_size,
  etag,
  last_modified_epoch_ms,
  storage_path,
  updated_token
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(artwork_key, variant) DO UPDATE SET
  mime_type = excluded.mime_type,
  byte_size = excluded.byte_size,
  etag = excluded.etag,
  last_modified_epoch_ms = excluded.last_modified_epoch_ms,
  storage_path = excluded.storage_path,
  updated_token = excluded.updated_token;
''',
      <Object?>[
        record.artworkKey,
        record.variant,
        record.mimeType,
        record.byteSize,
        record.etag,
        record.lastModifiedEpochMs,
        record.storagePath,
        record.updatedToken,
      ],
    );
  }

  CatalogWriteResult writeFullSnapshot({
    required LibraryStructure library,
    required String Function(String filePath) songIdForPath,
  }) {
    final albumsById = _buildAlbumSnapshots(library);
    final songsById = _buildSongSnapshots(library, songIdForPath);

    final existingAlbumIds = _selectActiveIds('albums');
    final existingSongIds = _selectActiveIds('songs');

    final deletedAlbumIds = existingAlbumIds
        .where((id) => !albumsById.containsKey(id))
        .toList()
      ..sort();
    final deletedSongIds = existingSongIds
        .where((id) => !songsById.containsKey(id))
        .toList()
      ..sort();

    final orderedAlbumIds = albumsById.keys.toList()..sort();
    final orderedSongIds = songsById.keys.toList()..sort();

    final occurredEpochMs = DateTime.now().millisecondsSinceEpoch;
    var tokenCursor = _readLatestToken();

    _database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final albumId in orderedAlbumIds) {
        tokenCursor += 1;
        final snapshot = albumsById[albumId]!;
        _repository.upsertAlbum(
          CatalogAlbumRecord(
            id: snapshot.id,
            title: snapshot.title,
            artist: snapshot.artist,
            year: snapshot.year,
            coverArtKey: snapshot.coverArtKey,
            songCount: snapshot.songCount,
            durationSeconds: snapshot.durationSeconds,
            updatedToken: tokenCursor,
          ),
        );
        _insertChangeEvent(
          entityType: 'album',
          entityId: snapshot.id,
          op: 'upsert',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in orderedSongIds) {
        tokenCursor += 1;
        final snapshot = songsById[songId]!;
        _repository.upsertSong(
          CatalogSongRecord(
            id: snapshot.id,
            filePath: snapshot.filePath,
            title: snapshot.title,
            artist: snapshot.artist,
            albumId: snapshot.albumId,
            durationSeconds: snapshot.durationSeconds,
            trackNumber: snapshot.trackNumber,
            fileSizeBytes: snapshot.fileSizeBytes,
            modifiedEpochMs: snapshot.modifiedEpochMs,
            artworkKey: snapshot.artworkKey,
            updatedToken: tokenCursor,
          ),
        );
        _insertChangeEvent(
          entityType: 'song',
          entityId: snapshot.id,
          op: 'upsert',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final songId in deletedSongIds) {
        tokenCursor += 1;
        _repository.softDeleteSong(songId, tokenCursor);
        _insertChangeEvent(
          entityType: 'song',
          entityId: songId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      for (final albumId in deletedAlbumIds) {
        tokenCursor += 1;
        _repository.softDeleteAlbum(albumId, tokenCursor);
        _insertChangeEvent(
          entityType: 'album',
          entityId: albumId,
          op: 'delete',
          occurredEpochMs: occurredEpochMs,
        );
      }

      _database.execute('COMMIT;');
    } catch (_) {
      _database.execute('ROLLBACK;');
      rethrow;
    }

    _latestToken = tokenCursor;
    return CatalogWriteResult(
      upsertedAlbumCount: orderedAlbumIds.length,
      upsertedSongCount: orderedSongIds.length,
      deletedAlbumCount: deletedAlbumIds.length,
      deletedSongCount: deletedSongIds.length,
      latestToken: tokenCursor,
    );
  }

  Map<String, _AlbumSnapshot> _buildAlbumSnapshots(LibraryStructure library) {
    final snapshots = <String, _AlbumSnapshot>{};
    for (final album in library.albums.values.where((a) => a.isValid)) {
      var durationSeconds = 0;
      for (final song in album.songs) {
        final duration = song.duration;
        if (duration != null && duration > 0) {
          durationSeconds += duration;
        }
      }

      snapshots[album.id] = _AlbumSnapshot(
        id: album.id,
        title: album.title,
        artist: album.artist,
        year: album.year,
        coverArtKey: album.artworkPath != null ? album.id : null,
        songCount: album.songCount,
        durationSeconds: durationSeconds,
      );
    }
    return snapshots;
  }

  Map<String, _SongSnapshot> _buildSongSnapshots(
    LibraryStructure library,
    String Function(String filePath) songIdForPath,
  ) {
    final snapshots = <String, _SongSnapshot>{};

    for (final album in library.albums.values.where((a) => a.isValid)) {
      for (final song in album.songs) {
        final snapshot = _songToSnapshot(
          song: song,
          songIdForPath: songIdForPath,
          albumId: album.id,
        );
        snapshots[snapshot.id] = snapshot;
      }
    }

    for (final song in library.standaloneSongs) {
      final snapshot = _songToSnapshot(
        song: song,
        songIdForPath: songIdForPath,
        albumId: null,
      );
      snapshots[snapshot.id] = snapshot;
    }

    return snapshots;
  }

  _SongSnapshot _songToSnapshot({
    required SongMetadata song,
    required String Function(String filePath) songIdForPath,
    required String? albumId,
  }) {
    final title = (song.title != null && song.title!.trim().isNotEmpty)
        ? song.title!.trim()
        : path.basenameWithoutExtension(song.filePath);
    final artist = (song.artist != null && song.artist!.trim().isNotEmpty)
        ? song.artist!.trim()
        : 'Unknown Artist';

    return _SongSnapshot(
      id: songIdForPath(song.filePath),
      filePath: song.filePath,
      title: title,
      artist: artist,
      albumId: albumId,
      durationSeconds: song.duration ?? 0,
      trackNumber: song.trackNumber,
      fileSizeBytes: song.fileSize,
      modifiedEpochMs: song.modifiedTime?.millisecondsSinceEpoch,
      artworkKey: albumId,
    );
  }

  List<String> _selectActiveIds(String tableName) {
    final rows = _database.select(
      '''
SELECT id
FROM $tableName
WHERE is_deleted = 0
ORDER BY id ASC;
''',
    );
    return rows.map((row) => row['id'] as String).toList();
  }

  int _readLatestToken() {
    final rows = _database.select(
      '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
    );
    return rows.first['latest_token'] as int;
  }

  void _insertChangeEvent({
    required String entityType,
    required String entityId,
    required String op,
    required int occurredEpochMs,
  }) {
    _database.execute(
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

class _AlbumSnapshot {
  _AlbumSnapshot({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.coverArtKey,
    required this.songCount,
    required this.durationSeconds,
  });

  final String id;
  final String title;
  final String artist;
  final int? year;
  final String? coverArtKey;
  final int songCount;
  final int durationSeconds;
}

class _SongSnapshot {
  _SongSnapshot({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.durationSeconds,
    required this.trackNumber,
    required this.fileSizeBytes,
    required this.modifiedEpochMs,
    required this.artworkKey,
  });

  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String? albumId;
  final int durationSeconds;
  final int? trackNumber;
  final int? fileSizeBytes;
  final int? modifiedEpochMs;
  final String? artworkKey;
}
