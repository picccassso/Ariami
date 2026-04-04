import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LibrarySyncState {
  final int lastAppliedToken;
  final bool bootstrapComplete;
  final int lastSyncEpochMs;

  const LibrarySyncState({
    required this.lastAppliedToken,
    required this.bootstrapComplete,
    required this.lastSyncEpochMs,
  });
}

class LibraryAlbumRow {
  final String id;
  final String title;
  final String artist;
  final String? coverArt;
  final int songCount;
  final int duration;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  const LibraryAlbumRow({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArt,
    required this.songCount,
    required this.duration,
    this.isDeleted = false,
    this.createdAt,
    this.modifiedAt,
  });
}

class LibrarySongRow {
  final String id;
  final String title;
  final String artist;
  final String? albumId;
  final int duration;
  final int? trackNumber;
  final bool isDeleted;

  const LibrarySongRow({
    required this.id,
    required this.title,
    required this.artist,
    this.albumId,
    required this.duration,
    this.trackNumber,
    this.isDeleted = false,
  });
}

class LibraryPlaylistRow {
  final String id;
  final String name;
  final int songCount;
  final int duration;
  final bool isDeleted;

  const LibraryPlaylistRow({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
    this.isDeleted = false,
  });
}

class LibraryPlaylistSongRow {
  final String playlistId;
  final String songId;
  final int position;
  final bool isDeleted;

  const LibraryPlaylistSongRow({
    required this.playlistId,
    required this.songId,
    required this.position,
    this.isDeleted = false,
  });
}

/// SQLite database for normalized library sync state.
class LibrarySyncDatabase {
  static const String _databaseName = 'library_sync.db';
  static const int _databaseVersion = 4;

  static const String _albumsTable = 'albums';
  static const String _songsTable = 'songs';
  static const String _playlistsTable = 'playlists';
  static const String _playlistSongsTable = 'playlist_songs';
  static const String _syncStateTable = 'sync_state';
  static const String _bootstrapAlbumsTable = 'bootstrap_staging_albums';
  static const String _bootstrapSongsTable = 'bootstrap_staging_songs';
  static const String _bootstrapPlaylistsTable = 'bootstrap_staging_playlists';
  static const String _bootstrapPlaylistSongsTable =
      'bootstrap_staging_playlist_songs';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<LibrarySyncDatabase> create() async {
    final db = LibrarySyncDatabase();
    await db.database;
    return db;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_albumsTable (
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
      CREATE TABLE $_songsTable (
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
      CREATE TABLE $_playlistsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        song_count INTEGER NOT NULL DEFAULT 0,
        duration INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $_playlistSongsTable (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, song_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $_syncStateTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_applied_token INTEGER NOT NULL DEFAULT 0,
        bootstrap_complete INTEGER NOT NULL DEFAULT 0,
        last_sync_epoch_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.insert(_syncStateTable, {
      'id': 1,
      'last_applied_token': 0,
      'bootstrap_complete': 0,
      'last_sync_epoch_ms': 0,
    });

    await db.execute(
      'CREATE INDEX idx_albums_is_deleted ON $_albumsTable (is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_is_deleted ON $_songsTable (is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_songs_album ON $_songsTable (album_id, is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlists_is_deleted ON $_playlistsTable (is_deleted, id)',
    );
    await db.execute(
      'CREATE INDEX idx_playlist_songs_playlist ON $_playlistSongsTable '
      '(playlist_id, is_deleted, position)',
    );

    await _createBootstrapStagingTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createBootstrapStagingTables(db);
    }
    if (oldVersion < 3) {
      await _migrateToVersion3(db);
    }
    if (oldVersion < 4) {
      await _createBootstrapStagingPlaylistSongsTable(db);
    }
  }

  Future<void> _migrateToVersion3(Database db) async {
    // Add created_at and modified_at columns to albums table
    await db.execute('ALTER TABLE $_albumsTable ADD COLUMN created_at INTEGER');
    await db
        .execute('ALTER TABLE $_albumsTable ADD COLUMN modified_at INTEGER');

    // Also add to bootstrap staging table
    await db.execute(
        'ALTER TABLE $_bootstrapAlbumsTable ADD COLUMN created_at INTEGER');
    await db.execute(
        'ALTER TABLE $_bootstrapAlbumsTable ADD COLUMN modified_at INTEGER');

    // Populate existing albums with current timestamp (since we don't have file access here)
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      _albumsTable,
      {'created_at': now, 'modified_at': now},
    );
  }

  Future<void> _createBootstrapStagingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_bootstrapAlbumsTable (
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
      CREATE TABLE IF NOT EXISTS $_bootstrapSongsTable (
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
      CREATE TABLE IF NOT EXISTS $_bootstrapPlaylistsTable (
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
      CREATE TABLE IF NOT EXISTS $_bootstrapPlaylistSongsTable (
        playlist_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (playlist_id, song_id)
      )
    ''');
  }

  Future<void> runInTransaction(
    Future<void> Function(Transaction txn) action,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await action(txn);
    });
  }

  Future<void> clearLibraryData({DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.delete(_playlistSongsTable);
    await db.delete(_playlistsTable);
    await db.delete(_songsTable);
    await db.delete(_albumsTable);
  }

  Future<void> clearBootstrapStagingData({DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.delete(_bootstrapPlaylistSongsTable);
    await db.delete(_bootstrapPlaylistsTable);
    await db.delete(_bootstrapSongsTable);
    await db.delete(_bootstrapAlbumsTable);
  }

  Future<void> upsertAlbums(
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) async {
    await _upsertAlbumsIntoTable(
      _albumsTable,
      albums,
      executor: executor,
    );
  }

  Future<void> upsertSongs(
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) async {
    await _upsertSongsIntoTable(
      _songsTable,
      songs,
      executor: executor,
    );
  }

  Future<void> upsertPlaylists(
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) async {
    await _upsertPlaylistsIntoTable(
      _playlistsTable,
      playlists,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingAlbums(
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) async {
    await _upsertAlbumsIntoTable(
      _bootstrapAlbumsTable,
      albums,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingSongs(
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) async {
    await _upsertSongsIntoTable(
      _bootstrapSongsTable,
      songs,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingPlaylists(
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) async {
    await _upsertPlaylistsIntoTable(
      _bootstrapPlaylistsTable,
      playlists,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingPlaylistSongs(
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    for (final item in playlistSongs) {
      await db.insert(
        _bootstrapPlaylistSongsTable,
        {
          'playlist_id': item.playlistId,
          'song_id': item.songId,
          'position': item.position,
          'is_deleted': item.isDeleted ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> replacePrimaryWithBootstrapStaging({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await clearLibraryData(executor: db);

    await db.rawInsert('''
      INSERT INTO $_albumsTable (id, title, artist, cover_art, song_count, duration, is_deleted)
      SELECT id, title, artist, cover_art, song_count, duration, is_deleted
      FROM $_bootstrapAlbumsTable
    ''');

    await db.rawInsert('''
      INSERT INTO $_songsTable (id, title, artist, album_id, duration, track_number, is_deleted)
      SELECT id, title, artist, album_id, duration, track_number, is_deleted
      FROM $_bootstrapSongsTable
    ''');

    await db.rawInsert('''
      INSERT INTO $_playlistsTable (id, name, song_count, duration, is_deleted)
      SELECT id, name, song_count, duration, is_deleted
      FROM $_bootstrapPlaylistsTable
    ''');

    await db.rawInsert('''
      INSERT INTO $_playlistSongsTable (playlist_id, song_id, position, is_deleted)
      SELECT playlist_id, song_id, position, is_deleted
      FROM $_bootstrapPlaylistSongsTable
    ''');
  }

  Future<void> upsertPlaylistSongs(
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    for (final item in playlistSongs) {
      await db.insert(
        _playlistSongsTable,
        {
          'playlist_id': item.playlistId,
          'song_id': item.songId,
          'position': item.position,
          'is_deleted': item.isDeleted ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> replacePlaylistSongs(
    String playlistId,
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.delete(
      _playlistSongsTable,
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await upsertPlaylistSongs(playlistSongs, executor: db);
  }

  Future<void> softDeleteAlbum(String id, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.update(
      _albumsTable,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteSong(String id, {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.update(
      _songsTable,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeletePlaylist(String id,
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    await db.update(
      _playlistsTable,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.update(
      _playlistSongsTable,
      {'is_deleted': 1},
      where: 'playlist_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeletePlaylistSong(
    String playlistId,
    String songId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.update(
      _playlistSongsTable,
      {'is_deleted': 1},
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
  }

  Future<LibraryAlbumRow?> getAlbumById(String id) async {
    final db = await database;
    final rows = await db.query(
      _albumsTable,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _albumFromMap(rows.first);
  }

  Future<LibrarySongRow?> getSongById(String id) async {
    final db = await database;
    final rows = await db.query(
      _songsTable,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _songFromMap(rows.first);
  }

  Future<List<LibraryAlbumRow>> listAlbums() async {
    final db = await database;
    final rows = await db.query(
      _albumsTable,
      where: 'is_deleted = 0',
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_albumFromMap).toList();
  }

  Future<List<LibrarySongRow>> listSongs() async {
    final db = await database;
    final rows = await db.query(
      _songsTable,
      where: 'is_deleted = 0',
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_songFromMap).toList();
  }

  Future<List<LibrarySongRow>> listSongsByAlbumId(String albumId) async {
    final db = await database;
    final rows = await db.query(
      _songsTable,
      where: 'album_id = ? AND is_deleted = 0',
      whereArgs: [albumId],
      orderBy: 'track_number ASC, title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_songFromMap).toList();
  }

  Future<List<LibraryPlaylistRow>> listPlaylists() async {
    final db = await database;
    final rows = await db.query(
      _playlistsTable,
      where: 'is_deleted = 0',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_playlistFromMap).toList();
  }

  Future<List<LibraryPlaylistSongRow>> listPlaylistSongs(
      String playlistId) async {
    final db = await database;
    final rows = await db.query(
      _playlistSongsTable,
      where: 'playlist_id = ? AND is_deleted = 0',
      whereArgs: [playlistId],
      orderBy: 'position ASC, song_id ASC',
    );
    return rows.map(_playlistSongFromMap).toList();
  }

  Future<LibrarySyncState> getSyncState({DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    final rows = await db.query(
      _syncStateTable,
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) {
      return const LibrarySyncState(
        lastAppliedToken: 0,
        bootstrapComplete: false,
        lastSyncEpochMs: 0,
      );
    }

    final row = rows.first;
    return LibrarySyncState(
      lastAppliedToken: row['last_applied_token'] as int? ?? 0,
      bootstrapComplete: (row['bootstrap_complete'] as int? ?? 0) == 1,
      lastSyncEpochMs: row['last_sync_epoch_ms'] as int? ?? 0,
    );
  }

  Future<bool> hasPlaylistMembershipBackfillPending({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    final rows = await db.rawQuery('''
      SELECT 1
      FROM $_playlistsTable playlists
      LEFT JOIN (
        SELECT playlist_id, COUNT(*) AS active_song_count
        FROM $_playlistSongsTable
        WHERE is_deleted = 0
        GROUP BY playlist_id
      ) playlist_songs
        ON playlist_songs.playlist_id = playlists.id
      WHERE playlists.is_deleted = 0
        AND playlists.song_count != COALESCE(playlist_songs.active_song_count, 0)
      LIMIT 1
    ''');
    return rows.isNotEmpty;
  }

  Future<void> saveSyncState(
    LibrarySyncState state, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.insert(
      _syncStateTable,
      {
        'id': 1,
        'last_applied_token': state.lastAppliedToken,
        'bootstrap_complete': state.bootstrapComplete ? 1 : 0,
        'last_sync_epoch_ms': state.lastSyncEpochMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  LibraryAlbumRow _albumFromMap(Map<String, Object?> row) {
    return LibraryAlbumRow(
      id: row['id'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      coverArt: row['cover_art'] as String?,
      songCount: row['song_count'] as int? ?? 0,
      duration: row['duration'] as int? ?? 0,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
      createdAt: row['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int)
          : null,
      modifiedAt: row['modified_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['modified_at'] as int)
          : null,
    );
  }

  LibrarySongRow _songFromMap(Map<String, Object?> row) {
    return LibrarySongRow(
      id: row['id'] as String,
      title: row['title'] as String,
      artist: row['artist'] as String,
      albumId: row['album_id'] as String?,
      duration: row['duration'] as int? ?? 0,
      trackNumber: row['track_number'] as int?,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
    );
  }

  LibraryPlaylistRow _playlistFromMap(Map<String, Object?> row) {
    return LibraryPlaylistRow(
      id: row['id'] as String,
      name: row['name'] as String,
      songCount: row['song_count'] as int? ?? 0,
      duration: row['duration'] as int? ?? 0,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
    );
  }

  LibraryPlaylistSongRow _playlistSongFromMap(Map<String, Object?> row) {
    return LibraryPlaylistSongRow(
      playlistId: row['playlist_id'] as String,
      songId: row['song_id'] as String,
      position: row['position'] as int? ?? 0,
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
    );
  }

  Future<void> _upsertAlbumsIntoTable(
    String table,
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    for (final album in albums) {
      await db.insert(
        table,
        {
          'id': album.id,
          'title': album.title,
          'artist': album.artist,
          'cover_art': album.coverArt,
          'song_count': album.songCount,
          'duration': album.duration,
          'is_deleted': album.isDeleted ? 1 : 0,
          'created_at': album.createdAt?.millisecondsSinceEpoch,
          'modified_at': album.modifiedAt?.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _upsertSongsIntoTable(
    String table,
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    for (final song in songs) {
      await db.insert(
        table,
        {
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'album_id': song.albumId,
          'duration': song.duration,
          'track_number': song.trackNumber,
          'is_deleted': song.isDeleted ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _upsertPlaylistsIntoTable(
    String table,
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    for (final playlist in playlists) {
      await db.insert(
        table,
        {
          'id': playlist.id,
          'name': playlist.name,
          'song_count': playlist.songCount,
          'duration': playlist.duration,
          'is_deleted': playlist.isDeleted ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
