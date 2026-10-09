import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../common/sqlite_image_store.dart';

class PlaylistImageInfo {
  const PlaylistImageInfo({
    required this.playlistId,
    required this.contentType,
    required this.updatedAt,
  });

  final String playlistId;
  final String contentType;

  /// Milliseconds since epoch (UTC). Strictly increases per playlist so
  /// clients can use it as a cache-busting version.
  final int updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'playlistId': playlistId,
        'contentType': contentType,
        'updatedAt': updatedAt,
      };
}

class PlaylistImageRecord extends PlaylistImageInfo {
  const PlaylistImageRecord({
    required super.playlistId,
    required super.contentType,
    required super.updatedAt,
    required this.bytes,
  });

  final Uint8List bytes;
}

/// SQLite persistence for account-scoped custom playlist images.
///
/// Images are the cover photos a user picks for a playlist on one client and
/// expects to see on every other client. They are keyed by the same playlist
/// ids as [PlaylistEditStore] rows (server folder-playlist ids and `created:`
/// ids), but live independently of edits: a playlist can have an image with
/// no edit and vice versa. Blobs are stored in the database rather than as
/// files so arbitrary playlist ids never have to be made filesystem-safe.
///
/// The HTTP layer supplies [userId] from a validated session. Client payloads
/// never select the account that is read or written.
class PlaylistImageStore extends SqliteImageStore {
  PlaylistImageStore({required super.databasePath})
      : super(
          storeName: 'PlaylistImageStore',
          table: 'playlist_images',
          keyColumn: 'playlist_id',
        );

  static const int maxPlaylistIdLength = 512;
  static const int maxImageBytes = 5 * 1024 * 1024;

  @override
  void createSchema(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS playlist_images (
        user_id TEXT NOT NULL,
        playlist_id TEXT NOT NULL,
        content_type TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        bytes BLOB NOT NULL,
        PRIMARY KEY (user_id, playlist_id)
      )
    ''');
  }

  List<PlaylistImageInfo> list(String userId) {
    final rows = db.select('''
      SELECT playlist_id, content_type, updated_at
      FROM playlist_images
      WHERE user_id = ?
      ORDER BY updated_at DESC, playlist_id ASC
    ''', <Object?>[userId]);
    return rows
        .map((row) => PlaylistImageInfo(
              playlistId: row['playlist_id'] as String,
              contentType: row['content_type'] as String,
              updatedAt: row['updated_at'] as int,
            ))
        .toList(growable: false);
  }

  PlaylistImageRecord? find(String userId, String playlistId) {
    final normalizedPlaylistId = _validatePlaylistId(playlistId);
    final rows = db.select('''
      SELECT playlist_id, content_type, updated_at, bytes
      FROM playlist_images
      WHERE user_id = ? AND playlist_id = ?
      LIMIT 1
    ''', <Object?>[userId, normalizedPlaylistId]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PlaylistImageRecord(
      playlistId: row['playlist_id'] as String,
      contentType: row['content_type'] as String,
      updatedAt: row['updated_at'] as int,
      bytes: row['bytes'] as Uint8List,
    );
  }

  PlaylistImageInfo put(
    String userId,
    String playlistId, {
    required List<int> bytes,
    required String contentType,
  }) {
    final normalizedPlaylistId = _validatePlaylistId(playlistId);
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw ArgumentError.value(
          bytes.length, 'bytes', 'Invalid image payload size');
    }

    final updatedAt = nextUpdatedAt(userId, normalizedPlaylistId);

    db.execute('''
      INSERT INTO playlist_images (
        user_id, playlist_id, content_type, updated_at, bytes
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id, playlist_id) DO UPDATE SET
        content_type = excluded.content_type,
        updated_at = excluded.updated_at,
        bytes = excluded.bytes
    ''', <Object?>[
      userId,
      normalizedPlaylistId,
      contentType,
      updatedAt,
      Uint8List.fromList(bytes),
    ]);
    return PlaylistImageInfo(
      playlistId: normalizedPlaylistId,
      contentType: contentType,
      updatedAt: updatedAt,
    );
  }

  @override
  StoredImage? findStoredImage(String userId, String key) {
    final record = find(userId, key);
    if (record == null) return null;
    return (
      key: record.playlistId,
      bytes: record.bytes,
      contentType: record.contentType,
      updatedAt: record.updatedAt,
    );
  }

  bool delete(String userId, String playlistId) =>
      deleteByKey(userId, _validatePlaylistId(playlistId));

  String _validatePlaylistId(String playlistId) {
    if (playlistId.trim().isEmpty || playlistId.length > maxPlaylistIdLength) {
      throw ArgumentError.value(
          playlistId, 'playlistId', 'Invalid playlist id');
    }
    return playlistId.trim();
  }
}
