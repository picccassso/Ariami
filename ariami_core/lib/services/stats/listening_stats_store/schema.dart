part of '../listening_stats_store.dart';

extension _ListeningStatsSchema on ListeningStatsStore {
  void _initializeStore() {
    if (_database != null) return;

    final parentDirectory = File(databasePath).parent;
    if (!parentDirectory.existsSync()) {
      parentDirectory.createSync(recursive: true);
    }

    final db = sqlite3.open(databasePath);
    try {
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA synchronous=NORMAL;');
      db.execute('PRAGMA busy_timeout=5000;');
      _createSchema(db);
      _migrateEventColumns(db);
      _backfillDerivedIfNeeded(db);
      _database = db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_events (
        event_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        play_id TEXT,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        plays INTEGER NOT NULL DEFAULT 0,
        occurred_at INTEGER NOT NULL,
        tz_offset_min INTEGER NOT NULL DEFAULT 0,
        received_at INTEGER NOT NULL,
        song_title TEXT,
        song_artist TEXT,
        album_id TEXT,
        album TEXT,
        album_artist TEXT,
        source_kind TEXT,
        playlist_id TEXT,
        client_kind TEXT
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_events_user_song
        ON listening_events (user_id, song_id)
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_events_user_time
        ON listening_events (user_id, occurred_at)
    ''');
    // Keeps the per-user 'spotify:*' event_id existence probe behind the
    // summary's hasSpotifyImport flag a single index seek, even on 200K+
    // event histories. Idempotent; no rollup schema version bump needed.
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_events_user_event
        ON listening_events (user_id, event_id)
    ''');
    // Second line of defence against double-counted plays: even if a buggy
    // client re-sends the same play-action under a fresh eventId, only one
    // play per (user, playId) can ever land.
    db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_listening_events_play_once
        ON listening_events (user_id, play_id)
        WHERE plays > 0 AND play_id IS NOT NULL
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_song_rollups (
        user_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        song_title TEXT,
        song_artist TEXT,
        album_id TEXT,
        album TEXT,
        album_artist TEXT,
        PRIMARY KEY (user_id, song_id)
      )
    ''');
    // Derived tables (rollup schema v2). All of these are disposable: they are
    // rebuilt from listening_events, never the other way around.
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_stats_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    // Current credited-artist list per (user, song), derived server-side from
    // the raw display artist string. The display string on events/rollups is
    // never modified; this table only adds the split view.
    db.execute('''
      CREATE TABLE IF NOT EXISTS song_artist_credits (
        user_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        artist_key TEXT NOT NULL,
        artist_display TEXT NOT NULL,
        ordinal INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, song_id, artist_key)
      )
    ''');
    // Every credited artist receives the FULL play and FULL listened time of
    // an event — credit is never divided between collaborators.
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_artist_rollups (
        user_id TEXT NOT NULL,
        artist_key TEXT NOT NULL,
        artist_display TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        PRIMARY KEY (user_id, artist_key)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_album_rollups (
        user_id TEXT NOT NULL,
        album_key TEXT NOT NULL,
        album TEXT,
        album_artist TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        first_played INTEGER,
        last_played INTEGER,
        PRIMARY KEY (user_id, album_key)
      )
    ''');
    // Generic local-day grain: any period view (day, week, month, year) is a
    // range query over these rows — months/years never need their own tables.
    // Baseline imports are excluded (they compress history into one moment).
    db.execute('''
      CREATE TABLE IF NOT EXISTS listening_daily_rollups (
        user_id TEXT NOT NULL,
        local_day TEXT NOT NULL,
        dim TEXT NOT NULL,
        dim_key TEXT NOT NULL,
        play_count INTEGER NOT NULL DEFAULT 0,
        listened_ms INTEGER NOT NULL DEFAULT 0,
        display TEXT,
        display_extra TEXT,
        PRIMARY KEY (user_id, local_day, dim, dim_key)
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_listening_daily_user_dim_day
        ON listening_daily_rollups (user_id, dim, local_day)
    ''');
  }

  /// Adds optional playback-context columns to databases created before those
  /// fields existed. The migration is additive and idempotent.
  void _migrateEventColumns(Database db) {
    final existing = db
        .select('PRAGMA table_info(listening_events)')
        .map((row) => row['name'] as String)
        .toSet();
    const contextColumns = ['source_kind', 'playlist_id', 'client_kind'];
    for (final column in contextColumns) {
      if (!existing.contains(column)) {
        db.execute('ALTER TABLE listening_events ADD COLUMN $column TEXT');
      }
    }
  }

  /// Rebuilds derived tables when their schema version changes.
  void _backfillDerivedIfNeeded(Database db) {
    final versionRows = db.select(
      "SELECT value FROM listening_stats_meta WHERE key = 'rollup_schema_version'",
    );
    final storedVersion = versionRows.isEmpty
        ? 0
        : int.tryParse(versionRows.first['value'] as String? ?? '') ?? 0;
    if (storedVersion >= ListeningStatsStore.rollupSchemaVersion) return;

    db.execute('BEGIN IMMEDIATE');
    try {
      final users = db.select('SELECT DISTINCT user_id FROM listening_events');
      for (final row in users) {
        _rebuildDerivedForUser(db, row['user_id'] as String);
      }
      db.execute('''
        INSERT INTO listening_stats_meta (key, value)
        VALUES ('rollup_schema_version', ?)
        ON CONFLICT (key) DO UPDATE SET value = excluded.value
      ''', ['${ListeningStatsStore.rollupSchemaVersion}']);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}
