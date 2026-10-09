import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../models/artist_image_info.dart';
import '../common/sqlite_image_store.dart';
import '../stats/credited_artist_splitter.dart';

/// SQLite persistence for account-scoped custom artist images.
///
/// Images are custom photos a user picks for an artist on one client (desktop or
/// mobile) and expects to see on every other client. They are keyed by
/// [userId] and normalized artist key (via [normalizeArtistKey]), but also
/// record the display artist name.
class ArtistImageStore extends SqliteImageStore {
  ArtistImageStore({required super.databasePath})
      : super(
          storeName: 'ArtistImageStore',
          table: 'artist_images',
          keyColumn: 'artist_key',
        );

  static const int maxArtistNameLength = 512;
  static const int maxImageBytes = 5 * 1024 * 1024;

  @override
  void createSchema(Database database) {
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
  }

  List<ArtistImageInfo> list(String userId) {
    final rows = db.select('''
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
    final rows = db.select('''
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

    final updatedAt = nextUpdatedAt(userId, artistKey);

    db.execute('''
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

  @override
  StoredImage? findStoredImage(String userId, String key) {
    final record = find(userId, key);
    if (record == null) return null;
    return (
      key: record.artistKey,
      bytes: record.bytes,
      contentType: record.contentType,
      updatedAt: record.updatedAt,
    );
  }

  bool delete(String userId, String artistNameOrKey) =>
      deleteByKey(userId, _validateAndNormalizeKey(artistNameOrKey));

  String _validateAndNormalizeKey(String artistNameOrKey) {
    final trimmed = artistNameOrKey.trim();
    if (trimmed.isEmpty || trimmed.length > maxArtistNameLength) {
      throw ArgumentError.value(
          artistNameOrKey, 'artistNameOrKey', 'Invalid artist name');
    }
    return normalizeArtistKey(trimmed);
  }
}
