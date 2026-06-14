import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:ariami_core/utils/text_sanitizer.dart';

/// Forward-only schema migrations for the catalog database.
class CatalogMigrations {
  static const int currentVersion = 5;

  static void migrate(Database database) {
    final existingVersion = database.userVersion;

    if (existingVersion > currentVersion) {
      throw StateError(
        'Catalog database version $existingVersion is newer than supported '
        'version $currentVersion.',
      );
    }

    if (existingVersion == currentVersion) {
      return;
    }

    database.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      if (existingVersion < 1) {
        _applyVersion1(database);
        database.userVersion = 1;
      }
      if (existingVersion < 2) {
        _applyVersion2(database);
        database.userVersion = 2;
      }
      if (existingVersion < 3) {
        _applyVersion3(database);
        database.userVersion = 3;
      }
      if (existingVersion < 4) {
        _applyVersion4(database);
        database.userVersion = 4;
      }
      if (existingVersion < 5) {
        _applyVersion5(database);
        database.userVersion = 5;
      }

      database.execute('COMMIT;');
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }
  }

  static void _applyVersion1(Database database) {
    database.execute('''
CREATE TABLE IF NOT EXISTS albums (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  year INTEGER NULL,
  cover_art_key TEXT NULL,
  song_count INTEGER NOT NULL,
  duration_seconds INTEGER NOT NULL,
  updated_token INTEGER NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS songs (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album_id TEXT NULL,
  duration_seconds INTEGER NOT NULL,
  track_number INTEGER NULL,
  file_size_bytes INTEGER NULL,
  modified_epoch_ms INTEGER NULL,
  bitrate_kbps INTEGER NULL,
  artwork_key TEXT NULL,
  updated_token INTEGER NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS playlists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  song_count INTEGER NOT NULL,
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  updated_token INTEGER NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS playlist_songs (
  playlist_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_token INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, position)
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS artwork_variants (
  artwork_key TEXT NOT NULL,
  variant TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  etag TEXT NOT NULL,
  last_modified_epoch_ms INTEGER NOT NULL,
  storage_path TEXT NOT NULL,
  updated_token INTEGER NOT NULL,
  PRIMARY KEY (artwork_key, variant)
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS library_changes (
  token INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,
  payload_json TEXT NULL,
  occurred_epoch_ms INTEGER NOT NULL,
  actor_user_id TEXT NULL
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS download_jobs (
  job_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  status TEXT NOT NULL,
  quality TEXT NOT NULL,
  download_original INTEGER NOT NULL,
  created_epoch_ms INTEGER NOT NULL,
  updated_epoch_ms INTEGER NOT NULL
);
''');

    database.execute('''
CREATE TABLE IF NOT EXISTS download_job_items (
  job_id TEXT NOT NULL,
  item_order INTEGER NOT NULL,
  song_id TEXT NOT NULL,
  status TEXT NOT NULL,
  error_code TEXT NULL,
  retry_after_epoch_ms INTEGER NULL,
  PRIMARY KEY (job_id, item_order)
);
''');

    database.execute('''
CREATE INDEX IF NOT EXISTS idx_songs_album_deleted_updated
ON songs(album_id, is_deleted, updated_token);
''');

    database.execute('''
CREATE INDEX IF NOT EXISTS idx_albums_deleted_updated
ON albums(is_deleted, updated_token);
''');

    database.execute('''
CREATE INDEX IF NOT EXISTS idx_library_changes_token
ON library_changes(token);
''');

    database.execute('''
CREATE INDEX IF NOT EXISTS idx_download_jobs_user_status
ON download_jobs(user_id, status);
''');
  }

  static void _applyVersion2(Database database) {
    database.execute('''
CREATE TABLE IF NOT EXISTS playlist_songs_v2 (
  playlist_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_token INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, position)
);
''');

    database.execute('''
INSERT INTO playlist_songs_v2 (
  playlist_id,
  song_id,
  position,
  updated_token
)
SELECT
  playlist_id,
  song_id,
  position,
  updated_token
FROM playlist_songs
ORDER BY playlist_id ASC, position ASC, song_id ASC;
''');

    database.execute('DROP TABLE playlist_songs;');
    database.execute(
      'ALTER TABLE playlist_songs_v2 RENAME TO playlist_songs;',
    );
  }

  static void _applyVersion3(Database database) {
    final existingColumns = database
        .select('PRAGMA table_info(playlists);')
        .map((row) => row['name'] as String)
        .toSet();
    if (existingColumns.contains('duration_seconds')) {
      return;
    }
    database.execute('''
ALTER TABLE playlists
ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0;
''');
  }

  static void _applyVersion4(Database database) {
    final existingColumns = database
        .select('PRAGMA table_info(songs);')
        .map((row) => row['name'] as String)
        .toSet();
    if (existingColumns.contains('bitrate_kbps')) {
      return;
    }
    database.execute('''
ALTER TABLE songs
ADD COLUMN bitrate_kbps INTEGER NULL;
''');
  }

  /// Scrubs invisible characters (NUL terminators from NUL-padded ID3v1 fields,
  /// zero-width and BOM chars, stray control codes) from text columns that were
  /// written by earlier scans before [sanitizeTagText] was applied at extraction
  /// time. Without this, otherwise-identical artist/album names compare as
  /// different and fragment downstream grouping (e.g. two "G-Eazy" entries).
  ///
  /// Done in Dart rather than SQL because SQLite's string functions treat an
  /// embedded NUL as a terminator, so a pure `REPLACE(...)` cannot remove it.
  ///
  /// The columns are read back via `CAST(... AS BLOB)` so the driver returns the
  /// full raw bytes (including the NUL): a plain text read is itself truncated at
  /// the first NUL, which would hide the very characters we need to strip.
  static void _applyVersion5(Database database) {
    _scrubTextColumn(database, table: 'songs', columns: ['title', 'artist']);
    _scrubTextColumn(database, table: 'albums', columns: ['title', 'artist']);
    _scrubTextColumn(database, table: 'playlists', columns: ['name']);
  }

  static void _scrubTextColumn(
    Database database, {
    required String table,
    required List<String> columns,
  }) {
    // Read each text column as a BLOB so embedded NULs survive the round-trip;
    // a TEXT read would be truncated at the first NUL byte.
    final selectCols = [
      'id',
      ...columns.map((c) => 'CAST($c AS BLOB) AS $c'),
    ].join(', ');
    final rows = database.select('SELECT $selectCols FROM $table;');

    final setClause = columns.map((c) => '$c = ?').join(', ');
    final update =
        database.prepare('UPDATE $table SET $setClause WHERE id = ?;');
    try {
      for (final row in rows) {
        final cleaned = <Object?>[];
        var changed = false;
        for (final c in columns) {
          final value = row[c];
          final original = value is Uint8List
              ? utf8.decode(value, allowMalformed: true)
              : value is String
                  ? value
                  : null;
          if (original != null) {
            final sanitized = sanitizeTagText(original);
            if (sanitized != original) changed = true;
            cleaned.add(sanitized);
          } else {
            cleaned.add(value);
          }
        }
        if (changed) {
          update.execute([...cleaned, row['id']]);
        }
      }
    } finally {
      update.close();
    }
  }
}
