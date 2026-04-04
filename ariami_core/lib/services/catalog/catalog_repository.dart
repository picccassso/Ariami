import 'package:sqlite3/sqlite3.dart';

class CatalogAlbumRecord {
  CatalogAlbumRecord({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.coverArtKey,
    required this.songCount,
    required this.durationSeconds,
    required this.updatedToken,
    this.isDeleted = false,
  });

  final String id;
  final String title;
  final String artist;
  final int? year;
  final String? coverArtKey;
  final int songCount;
  final int durationSeconds;
  final int updatedToken;
  final bool isDeleted;
}

class CatalogSongRecord {
  CatalogSongRecord({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    this.albumId,
    required this.durationSeconds,
    this.trackNumber,
    this.fileSizeBytes,
    this.modifiedEpochMs,
    this.artworkKey,
    required this.updatedToken,
    this.isDeleted = false,
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
  final int updatedToken;
  final bool isDeleted;
}

class CatalogPlaylistRecord {
  CatalogPlaylistRecord({
    required this.id,
    required this.name,
    required this.songCount,
    required this.durationSeconds,
    required this.updatedToken,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final int songCount;
  final int durationSeconds;
  final int updatedToken;
  final bool isDeleted;
}

class CatalogPlaylistSongRecord {
  CatalogPlaylistSongRecord({
    required this.playlistId,
    required this.songId,
    required this.position,
    required this.updatedToken,
  });

  final String playlistId;
  final String songId;
  final int position;
  final int updatedToken;
}

class CatalogChangeEventInput {
  CatalogChangeEventInput({
    required this.entityType,
    required this.entityId,
    required this.op,
    this.payloadJson,
    required this.occurredEpochMs,
    this.actorUserId,
  });

  final String entityType;
  final String entityId;
  final String op;
  final String? payloadJson;
  final int occurredEpochMs;
  final String? actorUserId;
}

class CatalogChangeEventRecord {
  CatalogChangeEventRecord({
    required this.token,
    required this.entityType,
    required this.entityId,
    required this.op,
    this.payloadJson,
    required this.occurredEpochMs,
    this.actorUserId,
  });

  final int token;
  final String entityType;
  final String entityId;
  final String op;
  final String? payloadJson;
  final int occurredEpochMs;
  final String? actorUserId;
}

class CatalogPage<T> {
  CatalogPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
  final int limit;
}

class CatalogRepository {
  CatalogRepository({required Database database}) : _database = database;

  final Database _database;

  void upsertAlbum(CatalogAlbumRecord album) {
    _database.execute(
      '''
INSERT INTO albums (
  id,
  title,
  artist,
  year,
  cover_art_key,
  song_count,
  duration_seconds,
  updated_token,
  is_deleted
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  artist = excluded.artist,
  year = excluded.year,
  cover_art_key = excluded.cover_art_key,
  song_count = excluded.song_count,
  duration_seconds = excluded.duration_seconds,
  updated_token = excluded.updated_token,
  is_deleted = excluded.is_deleted;
''',
      <Object?>[
        album.id,
        album.title,
        album.artist,
        album.year,
        album.coverArtKey,
        album.songCount,
        album.durationSeconds,
        album.updatedToken,
        album.isDeleted ? 1 : 0,
      ],
    );
  }

  void upsertSong(CatalogSongRecord song) {
    _database.execute(
      '''
INSERT INTO songs (
  id,
  file_path,
  title,
  artist,
  album_id,
  duration_seconds,
  track_number,
  file_size_bytes,
  modified_epoch_ms,
  artwork_key,
  updated_token,
  is_deleted
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  file_path = excluded.file_path,
  title = excluded.title,
  artist = excluded.artist,
  album_id = excluded.album_id,
  duration_seconds = excluded.duration_seconds,
  track_number = excluded.track_number,
  file_size_bytes = excluded.file_size_bytes,
  modified_epoch_ms = excluded.modified_epoch_ms,
  artwork_key = excluded.artwork_key,
  updated_token = excluded.updated_token,
  is_deleted = excluded.is_deleted;
''',
      <Object?>[
        song.id,
        song.filePath,
        song.title,
        song.artist,
        song.albumId,
        song.durationSeconds,
        song.trackNumber,
        song.fileSizeBytes,
        song.modifiedEpochMs,
        song.artworkKey,
        song.updatedToken,
        song.isDeleted ? 1 : 0,
      ],
    );
  }

  void upsertPlaylist(CatalogPlaylistRecord playlist) {
    _database.execute(
      '''
INSERT INTO playlists (
  id,
  name,
  song_count,
  duration_seconds,
  updated_token,
  is_deleted
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  song_count = excluded.song_count,
  duration_seconds = excluded.duration_seconds,
  updated_token = excluded.updated_token,
  is_deleted = excluded.is_deleted;
''',
      <Object?>[
        playlist.id,
        playlist.name,
        playlist.songCount,
        playlist.durationSeconds,
        playlist.updatedToken,
        playlist.isDeleted ? 1 : 0,
      ],
    );
  }

  void upsertPlaylistSong(CatalogPlaylistSongRecord playlistSong) {
    _database.execute(
      '''
INSERT INTO playlist_songs (
  playlist_id,
  song_id,
  position,
  updated_token
) VALUES (?, ?, ?, ?)
ON CONFLICT(playlist_id, position) DO UPDATE SET
  song_id = excluded.song_id,
  position = excluded.position,
  updated_token = excluded.updated_token;
''',
      <Object?>[
        playlistSong.playlistId,
        playlistSong.songId,
        playlistSong.position,
        playlistSong.updatedToken,
      ],
    );
  }

  void softDeleteAlbum(String albumId, int updatedToken) {
    _database.execute(
      '''
UPDATE albums
SET is_deleted = 1, updated_token = ?
WHERE id = ?;
''',
      <Object?>[updatedToken, albumId],
    );
  }

  void softDeleteSong(String songId, int updatedToken) {
    _database.execute(
      '''
UPDATE songs
SET is_deleted = 1, updated_token = ?
WHERE id = ?;
''',
      <Object?>[updatedToken, songId],
    );
  }

  void softDeletePlaylist(String playlistId, int updatedToken) {
    _database.execute(
      '''
UPDATE playlists
SET is_deleted = 1, updated_token = ?
WHERE id = ?;
''',
      <Object?>[updatedToken, playlistId],
    );
    _database.execute(
      '''
DELETE FROM playlist_songs
WHERE playlist_id = ?;
''',
      <Object?>[playlistId],
    );
  }

  void deletePlaylistSong(
    String playlistId,
    int position,
  ) {
    _database.execute(
      '''
DELETE FROM playlist_songs
WHERE playlist_id = ? AND position = ?;
''',
      <Object?>[playlistId, position],
    );
  }

  CatalogPage<CatalogAlbumRecord> listAlbumsPage({
    String? cursor,
    int limit = 100,
  }) {
    _validateLimit(limit);
    final int fetchLimit = limit + 1;
    final ResultSet rows = cursor == null
        ? _database.select(
            '''
SELECT
  id,
  title,
  artist,
  year,
  cover_art_key,
  song_count,
  duration_seconds,
  updated_token,
  is_deleted
FROM albums
WHERE is_deleted = 0
ORDER BY id ASC
LIMIT ?;
''',
            <Object?>[fetchLimit],
          )
        : _database.select(
            '''
SELECT
  id,
  title,
  artist,
  year,
  cover_art_key,
  song_count,
  duration_seconds,
  updated_token,
  is_deleted
FROM albums
WHERE is_deleted = 0 AND id > ?
ORDER BY id ASC
LIMIT ?;
''',
            <Object?>[cursor, fetchLimit],
          );

    final bool hasMore = rows.length > limit;
    final List<Row> pageRows =
        hasMore ? rows.take(limit).toList() : rows.toList();
    final List<CatalogAlbumRecord> items =
        pageRows.map(_mapAlbumRecord).toList();
    final String? nextCursor =
        hasMore && items.isNotEmpty ? items.last.id : null;

    return CatalogPage<CatalogAlbumRecord>(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
      limit: limit,
    );
  }

  CatalogPage<CatalogSongRecord> listSongsPage({
    String? cursor,
    int limit = 100,
  }) {
    _validateLimit(limit);
    final int fetchLimit = limit + 1;
    final ResultSet rows = cursor == null
        ? _database.select(
            '''
SELECT
  id,
  file_path,
  title,
  artist,
  album_id,
  duration_seconds,
  track_number,
  file_size_bytes,
  modified_epoch_ms,
  artwork_key,
  updated_token,
  is_deleted
FROM songs
WHERE is_deleted = 0
ORDER BY id ASC
LIMIT ?;
''',
            <Object?>[fetchLimit],
          )
        : _database.select(
            '''
SELECT
  id,
  file_path,
  title,
  artist,
  album_id,
  duration_seconds,
  track_number,
  file_size_bytes,
  modified_epoch_ms,
  artwork_key,
  updated_token,
  is_deleted
FROM songs
WHERE is_deleted = 0 AND id > ?
ORDER BY id ASC
LIMIT ?;
''',
            <Object?>[cursor, fetchLimit],
          );

    final bool hasMore = rows.length > limit;
    final List<Row> pageRows =
        hasMore ? rows.take(limit).toList() : rows.toList();
    final List<CatalogSongRecord> items = pageRows.map(_mapSongRecord).toList();
    final String? nextCursor =
        hasMore && items.isNotEmpty ? items.last.id : null;

    return CatalogPage<CatalogSongRecord>(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
      limit: limit,
    );
  }

  CatalogPage<CatalogPlaylistRecord> listPlaylistsPage({
    String? cursor,
    int limit = 100,
  }) {
    _validateLimit(limit);
    final int fetchLimit = limit + 1;
    final ResultSet rows = cursor == null
        ? _database.select(
            '''
SELECT
  id,
  name,
  song_count,
  duration_seconds,
  updated_token,
  is_deleted
FROM playlists
WHERE is_deleted = 0
ORDER BY id ASC
LIMIT ?;
''',
            <Object?>[fetchLimit],
          )
        : _database.select(
            '''
SELECT
  id,
  name,
  song_count,
  duration_seconds,
  updated_token,
  is_deleted
FROM playlists
WHERE is_deleted = 0 AND id > ?
ORDER BY id ASC
LIMIT ?;
''',
            <Object?>[cursor, fetchLimit],
          );

    final bool hasMore = rows.length > limit;
    final List<Row> pageRows =
        hasMore ? rows.take(limit).toList() : rows.toList();
    final List<CatalogPlaylistRecord> items =
        pageRows.map(_mapPlaylistRecord).toList();
    final String? nextCursor =
        hasMore && items.isNotEmpty ? items.last.id : null;

    return CatalogPage<CatalogPlaylistRecord>(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
      limit: limit,
    );
  }

  List<CatalogPlaylistSongRecord> listPlaylistSongs(String playlistId) {
    final ResultSet rows = _database.select(
      '''
SELECT
  playlist_id,
  song_id,
  position,
  updated_token
FROM playlist_songs
WHERE playlist_id = ?
ORDER BY position ASC, song_id ASC;
''',
      <Object?>[playlistId],
    );

    return rows.map(_mapPlaylistSongRecord).toList();
  }

  void appendChangeEvents(List<CatalogChangeEventInput> events) {
    if (events.isEmpty) {
      return;
    }

    _database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      for (final CatalogChangeEventInput event in events) {
        _database.execute(
          '''
INSERT INTO library_changes (
  entity_type,
  entity_id,
  op,
  payload_json,
  occurred_epoch_ms,
  actor_user_id
) VALUES (?, ?, ?, ?, ?, ?);
''',
          <Object?>[
            event.entityType,
            event.entityId,
            event.op,
            event.payloadJson,
            event.occurredEpochMs,
            event.actorUserId,
          ],
        );
      }
      _database.execute('COMMIT;');
    } catch (_) {
      _database.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<CatalogChangeEventRecord> readChangesSince(int sinceToken, int limit) {
    _validateLimit(limit);
    final ResultSet rows = _database.select(
      '''
SELECT
  token,
  entity_type,
  entity_id,
  op,
  payload_json,
  occurred_epoch_ms,
  actor_user_id
FROM library_changes
WHERE token > ?
ORDER BY token ASC
LIMIT ?;
''',
      <Object?>[sinceToken, limit],
    );

    return rows.map(_mapChangeEventRecord).toList();
  }

  int getLatestToken() {
    final ResultSet rows = _database.select(
      '''
SELECT COALESCE(MAX(token), 0) AS latest_token
FROM library_changes;
''',
    );
    return rows.first['latest_token'] as int;
  }

  CatalogAlbumRecord _mapAlbumRecord(Row row) {
    return CatalogAlbumRecord(
      id: row['id'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      year: row['year'] as int?,
      coverArtKey: row['cover_art_key'] as String?,
      songCount: row['song_count'] as int,
      durationSeconds: row['duration_seconds'] as int,
      updatedToken: row['updated_token'] as int,
      isDeleted: (row['is_deleted'] as int) == 1,
    );
  }

  CatalogSongRecord _mapSongRecord(Row row) {
    return CatalogSongRecord(
      id: row['id'] as String,
      filePath: row['file_path'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      albumId: row['album_id'] as String?,
      durationSeconds: row['duration_seconds'] as int,
      trackNumber: row['track_number'] as int?,
      fileSizeBytes: row['file_size_bytes'] as int?,
      modifiedEpochMs: row['modified_epoch_ms'] as int?,
      artworkKey: row['artwork_key'] as String?,
      updatedToken: row['updated_token'] as int,
      isDeleted: (row['is_deleted'] as int) == 1,
    );
  }

  CatalogPlaylistRecord _mapPlaylistRecord(Row row) {
    return CatalogPlaylistRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      songCount: row['song_count'] as int,
      durationSeconds: row['duration_seconds'] as int? ?? 0,
      updatedToken: row['updated_token'] as int,
      isDeleted: (row['is_deleted'] as int) == 1,
    );
  }

  CatalogPlaylistSongRecord _mapPlaylistSongRecord(Row row) {
    return CatalogPlaylistSongRecord(
      playlistId: row['playlist_id'] as String,
      songId: row['song_id'] as String,
      position: row['position'] as int,
      updatedToken: row['updated_token'] as int,
    );
  }

  CatalogChangeEventRecord _mapChangeEventRecord(Row row) {
    return CatalogChangeEventRecord(
      token: row['token'] as int,
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      op: row['op'] as String,
      payloadJson: row['payload_json'] as String?,
      occurredEpochMs: row['occurred_epoch_ms'] as int,
      actorUserId: row['actor_user_id'] as String?,
    );
  }

  void _validateLimit(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
    }
  }
}
