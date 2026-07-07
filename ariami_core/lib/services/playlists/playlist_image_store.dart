import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Metadata for a stored playlist image, without the bytes.
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

/// A stored playlist image, including its bytes.
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
class PlaylistImageStore {
  PlaylistImageStore({required this.databasePath});

  static const int maxPlaylistIdLength = 512;
  static const int maxImageBytes = 5 * 1024 * 1024;

  final String databasePath;
  Database? _database;

  bool get isInitialized => _database != null;

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('PlaylistImageStore is not initialized');
    }
    return database;
  }

  void initialize() {
    if (_database != null) return;
    final parent = File(databasePath).parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    final database = sqlite3.open(databasePath);
    try {
      database.execute('PRAGMA journal_mode=WAL;');
      database.execute('PRAGMA synchronous=NORMAL;');
      database.execute('PRAGMA busy_timeout=5000;');
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
      _database = database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  /// Lists image metadata (no bytes) for every playlist image of [userId].
  List<PlaylistImageInfo> list(String userId) {
    final rows = _db.select('''
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
    final rows = _db.select('''
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

    // Strictly monotonic per playlist so a replaced image always gets a new
    // version, even within one clock millisecond.
    final previous = _findUpdatedAt(userId, normalizedPlaylistId);
    var updatedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (previous != null && updatedAt <= previous) {
      updatedAt = previous + 1;
    }

    _db.execute('''
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

  bool delete(String userId, String playlistId) {
    final normalizedPlaylistId = _validatePlaylistId(playlistId);
    _db.execute(
      'DELETE FROM playlist_images WHERE user_id = ? AND playlist_id = ?',
      <Object?>[userId, normalizedPlaylistId],
    );
    return _db.updatedRows > 0;
  }

  int? _findUpdatedAt(String userId, String playlistId) {
    final rows = _db.select(
      'SELECT updated_at FROM playlist_images '
      'WHERE user_id = ? AND playlist_id = ? LIMIT 1',
      <Object?>[userId, playlistId],
    );
    return rows.isEmpty ? null : rows.first['updated_at'] as int;
  }

  String _validatePlaylistId(String playlistId) {
    if (playlistId.trim().isEmpty || playlistId.length > maxPlaylistIdLength) {
      throw ArgumentError.value(
          playlistId, 'playlistId', 'Invalid playlist id');
    }
    return playlistId.trim();
  }

  void close() {
    _database?.close();
    _database = null;
  }
}
