part of 'library_sync_database.dart';

class _LibrarySyncDatabaseSchema {
  const _LibrarySyncDatabaseSchema();

  Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${LibrarySyncDatabase._albumsTable} (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        cover_art TEXT,
        song_count INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER,
        modified_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LibrarySyncDatabase._songsTable} (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album_id TEXT,
        duration INTEGER NOT NULL DEFAULT 0,
        track_number INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LibrarySyncDatabase._playlistsTable} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        song_count INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LibrarySyncDatabase._playlistSongsTable} (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, position)
      )
    ''');

    await db.execute('''
      CREATE TABLE ${LibrarySyncDatabase._syncStateTable} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_applied_token INTEGER NOT NULL DEFAULT 0,
        bootstrap_complete INTEGER NOT NULL DEFAULT 0,
        last_sync_epoch_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.insert(LibrarySyncDatabase._syncStateTable, {
      'id': 1,
      'last_applied_token': 0,
      'bootstrap_complete': 0,
      'last_sync_epoch_ms': 0,
    });

    await db.execute(
      'CREATE INDEX idx_albums_is_deleted '
      'ON ${LibrarySyncDatabase._albumsTable} (is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_is_deleted '
      'ON ${LibrarySyncDatabase._songsTable} (is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_album '
      'ON ${LibrarySyncDatabase._songsTable} (album_id, is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlists_is_deleted '
      'ON ${LibrarySyncDatabase._playlistsTable} (is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_songs_playlist '
      'ON ${LibrarySyncDatabase._playlistSongsTable} '
      '(playlist_id, is_deleted, position)',
    );

    await _createBootstrapStagingTables(db);
  }

  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createBootstrapStagingTables(db);
    }
    if (oldVersion < 3) {
      await _migrateToVersion3(db);
    }
    if (oldVersion < 4) {
      await _createBootstrapStagingPlaylistSongsTable(db);
    }
    if (oldVersion < 5) {
      await _migratePlaylistSongTablesToPositionPrimaryKey(db);
    }
  }

  Future<void> _migrateToVersion3(Database db) async {
    await db.execute(
      'ALTER TABLE ${LibrarySyncDatabase._albumsTable} '
      'ADD COLUMN created_at INTEGER',
    );
    await db.execute(
      'ALTER TABLE ${LibrarySyncDatabase._albumsTable} '
      'ADD COLUMN modified_at INTEGER',
    );

    await db.execute(
      'ALTER TABLE ${LibrarySyncDatabase._bootstrapAlbumsTable} '
      'ADD COLUMN created_at INTEGER',
    );
    await db.execute(
      'ALTER TABLE ${LibrarySyncDatabase._bootstrapAlbumsTable} '
      'ADD COLUMN modified_at INTEGER',
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      LibrarySyncDatabase._albumsTable,
      {'created_at': now, 'modified_at': now},
    );
  }

  Future<void> _createBootstrapStagingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LibrarySyncDatabase._bootstrapAlbumsTable} (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        cover_art TEXT,
        song_count INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER,
        modified_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LibrarySyncDatabase._bootstrapSongsTable} (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album_id TEXT,
        duration INTEGER NOT NULL DEFAULT 0,
        track_number INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${LibrarySyncDatabase._bootstrapPlaylistsTable} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        song_count INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createBootstrapStagingPlaylistSongsTable(db);
  }

  Future<void> _createBootstrapStagingPlaylistSongsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS
      ${LibrarySyncDatabase._bootstrapPlaylistSongsTable} (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, position)
      )
    ''');
  }

  Future<void> _migratePlaylistSongTablesToPositionPrimaryKey(
    Database db,
  ) async {
    await _rebuildPlaylistSongTableWithPositionPrimaryKey(
      db,
      LibrarySyncDatabase._playlistSongsTable,
    );
    await _rebuildPlaylistSongTableWithPositionPrimaryKey(
      db,
      LibrarySyncDatabase._bootstrapPlaylistSongsTable,
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist '
      'ON ${LibrarySyncDatabase._playlistSongsTable} '
      '(playlist_id, is_deleted, position)',
    );
  }

  Future<void> _rebuildPlaylistSongTableWithPositionPrimaryKey(
    Database db,
    String tableName,
  ) async {
    final rebuiltTableName = '${tableName}_v5';
    await db.execute('DROP TABLE IF EXISTS $rebuiltTableName');
    await db.execute('''
      CREATE TABLE $rebuiltTableName (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, position)
      )
    ''');
    await db.execute('''
      INSERT INTO $rebuiltTableName (
        playlist_id,
        song_id,
        position,
        is_deleted
      )
      SELECT
        playlist_id,
        song_id,
        position,
        is_deleted
      FROM $tableName
      ORDER BY playlist_id ASC, position ASC, song_id ASC
    ''');
    await db.execute('DROP TABLE $tableName');
    await db.execute('ALTER TABLE $rebuiltTableName RENAME TO $tableName');
  }
}
