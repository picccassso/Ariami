import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../models/artist_image_info.dart';
import '../stats/credited_artist_splitter.dart';

/// SQLite persistence for account-scoped custom artist images.
///
/// Images are custom photos a user picks for an artist on one client (desktop or
/// mobile) and expects to see on every other client. They are keyed by
/// [userId] and normalized artist key (via [normalizeArtistKey]), but also
/// record the display artist name.
class ArtistImageStore {
  ArtistImageStore({required this.databasePath});

  static const int maxArtistNameLength = 512;
  static const int maxImageBytes = 5 * 1024 * 1024;

  final String databasePath;
  Database? _database;

  bool get isInitialized => _database != null;

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('ArtistImageStore is not initialized');
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
        CREATE TABLE IF NOT EXISTS artist_images (
          user_id TEXT NOT NULL,
          artist_key TEXT NOT NULL,
          artist_name TEXT NOT NULL,
          content_type TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          bytes BLOB NOT NULL,
          PRIMARY KEY (user_id, artist_key)
        )
      ''');
      _database = database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  /// Lists image metadata (no bytes) for every artist image belonging to [userId].
  List<ArtistImageInfo> list(String userId) {
    final rows = _db.select('''
      SELECT artist_key, artist_name, content_type, updated_at
      FROM artist_images
      WHERE user_id = ?
      ORDER BY updated_at DESC, artist_key ASC
    ''', <Object?>[userId]);
    return rows
        .map((row) => ArtistImageInfo(
              artistKey: row['artist_key'] as String,
              artistName: row['artist_name'] as String,
              contentType: row['content_type'] as String,
              updatedAt: row['updated_at'] as int,
            ))
        .toList(growable: false);
  }

  /// Finds the stored artist image record (including raw image bytes) by artist
  /// name or normalized key.
  ArtistImageRecord? find(String userId, String artistNameOrKey) {
    final artistKey = _validateAndNormalizeKey(artistNameOrKey);
    final rows = _db.select('''
      SELECT artist_key, artist_name, content_type, updated_at, bytes
      FROM artist_images
      WHERE user_id = ? AND artist_key = ?
      LIMIT 1
    ''', <Object?>[userId, artistKey]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ArtistImageRecord(
      artistKey: row['artist_key'] as String,
      artistName: row['artist_name'] as String,
      contentType: row['content_type'] as String,
      updatedAt: row['updated_at'] as int,
      bytes: row['bytes'] as Uint8List,
    );
  }

  /// Stores or updates an artist's custom image.
  ArtistImageInfo put(
    String userId,
    String artistName, {
    required List<int> bytes,
    required String contentType,
  }) {
    final trimmedName = artistName.trim();
    if (trimmedName.isEmpty || trimmedName.length > maxArtistNameLength) {
      throw ArgumentError.value(
          artistName, 'artistName', 'Invalid artist name');
    }
    final artistKey = normalizeArtistKey(trimmedName);
    if (artistKey.isEmpty) {
      throw ArgumentError.value(
          artistName, 'artistName', 'Invalid artist name');
    }

    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw ArgumentError.value(
          bytes.length, 'bytes', 'Invalid image payload size');
    }

    // Strictly monotonic per artist so a replaced image always gets a new
    // version, even within one clock millisecond.
    final previous = _findUpdatedAt(userId, artistKey);
    var updatedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (previous != null && updatedAt <= previous) {
      updatedAt = previous + 1;
    }

    _db.execute('''
      INSERT INTO artist_images (
        user_id, artist_key, artist_name, content_type, updated_at, bytes
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, artist_key) DO UPDATE SET
        artist_name = excluded.artist_name,
        content_type = excluded.content_type,
        updated_at = excluded.updated_at,
        bytes = excluded.bytes
    ''', <Object?>[
      userId,
      artistKey,
      trimmedName,
      contentType,
      updatedAt,
      Uint8List.fromList(bytes),
    ]);

    return ArtistImageInfo(
      artistKey: artistKey,
      artistName: trimmedName,
      contentType: contentType,
      updatedAt: updatedAt,
    );
  }

  /// Removes an artist's custom image.
  bool delete(String userId, String artistNameOrKey) {
    final artistKey = _validateAndNormalizeKey(artistNameOrKey);
    _db.execute(
      'DELETE FROM artist_images WHERE user_id = ? AND artist_key = ?',
      <Object?>[userId, artistKey],
    );
    return _db.updatedRows > 0;
  }

  int? _findUpdatedAt(String userId, String artistKey) {
    final rows = _db.select(
      'SELECT updated_at FROM artist_images '
      'WHERE user_id = ? AND artist_key = ? LIMIT 1',
      <Object?>[userId, artistKey],
    );
    return rows.isEmpty ? null : rows.first['updated_at'] as int;
  }

  String _validateAndNormalizeKey(String artistNameOrKey) {
    final trimmed = artistNameOrKey.trim();
    if (trimmed.isEmpty || trimmed.length > maxArtistNameLength) {
      throw ArgumentError.value(
          artistNameOrKey, 'artistNameOrKey', 'Invalid artist name');
    }
    return normalizeArtistKey(trimmed);
  }

  void close() {
    _database?.close();
    _database = null;
  }
}
