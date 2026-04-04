import 'package:sqlite3/sqlite3.dart';

/// Forward-only schema migrations for the catalog database.
class CatalogMigrations {
  static const int currentVersion = 3;

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
}
