part of 'library_sync_database.dart';

class _LibrarySyncDatabaseWrites {
  _LibrarySyncDatabaseWrites(this._owner);

  final LibrarySyncDatabase _owner;

  Future<void> clearLibraryData({DatabaseExecutor? executor}) async {
    final db = executor ?? await _owner.database;
    await db.delete(LibrarySyncDatabase._playlistSongsTable);
    await db.delete(LibrarySyncDatabase._playlistsTable);
    await db.delete(LibrarySyncDatabase._songsTable);
    await db.delete(LibrarySyncDatabase._albumsTable);
  }

  Future<void> clearBootstrapStagingData({DatabaseExecutor? executor}) async {
    final db = executor ?? await _owner.database;
    await db.delete(LibrarySyncDatabase._bootstrapPlaylistSongsTable);
    await db.delete(LibrarySyncDatabase._bootstrapPlaylistsTable);
    await db.delete(LibrarySyncDatabase._bootstrapSongsTable);
    await db.delete(LibrarySyncDatabase._bootstrapAlbumsTable);
  }

  Future<void> upsertAlbums(
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) {
    return _upsertAlbumsIntoTable(
      LibrarySyncDatabase._albumsTable,
      albums,
      executor: executor,
    );
  }

  Future<void> upsertSongs(
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) {
    return _upsertSongsIntoTable(
      LibrarySyncDatabase._songsTable,
      songs,
      executor: executor,
    );
  }

  Future<void> upsertPlaylists(
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) {
    return _upsertPlaylistsIntoTable(
      LibrarySyncDatabase._playlistsTable,
      playlists,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingAlbums(
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) {
    return _upsertAlbumsIntoTable(
      LibrarySyncDatabase._bootstrapAlbumsTable,
      albums,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingSongs(
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) {
    return _upsertSongsIntoTable(
      LibrarySyncDatabase._bootstrapSongsTable,
      songs,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingPlaylists(
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) {
    return _upsertPlaylistsIntoTable(
      LibrarySyncDatabase._bootstrapPlaylistsTable,
      playlists,
      executor: executor,
    );
  }

  Future<void> upsertBootstrapStagingPlaylistSongs(
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    for (final item in playlistSongs) {
      await db.insert(
        LibrarySyncDatabase._bootstrapPlaylistSongsTable,
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
    final db = executor ?? await _owner.database;
    await clearLibraryData(executor: db);

    await db.rawInsert('''
      INSERT INTO ${LibrarySyncDatabase._albumsTable}
      (id, title, artist, cover_art, song_count, duration, is_deleted)
      SELECT id, title, artist, cover_art, song_count, duration, is_deleted
      FROM ${LibrarySyncDatabase._bootstrapAlbumsTable}
    ''');

    await db.rawInsert('''
      INSERT INTO ${LibrarySyncDatabase._songsTable}
      (id, title, artist, album_id, duration, track_number, is_deleted)
      SELECT id, title, artist, album_id, duration, track_number, is_deleted
      FROM ${LibrarySyncDatabase._bootstrapSongsTable}
    ''');

    await db.rawInsert('''
      INSERT INTO ${LibrarySyncDatabase._playlistsTable}
      (id, name, song_count, duration, is_deleted)
      SELECT id, name, song_count, duration, is_deleted
      FROM ${LibrarySyncDatabase._bootstrapPlaylistsTable}
    ''');

    await db.rawInsert('''
      INSERT INTO ${LibrarySyncDatabase._playlistSongsTable}
      (playlist_id, song_id, position, is_deleted)
      SELECT playlist_id, song_id, position, is_deleted
      FROM ${LibrarySyncDatabase._bootstrapPlaylistSongsTable}
    ''');

    // Keep playlist counts aligned with the actual membership rows in case the
    // bootstrap payload carried stale song_count values.
    await db.rawUpdate('''
      UPDATE ${LibrarySyncDatabase._playlistsTable}
      SET song_count = (
        SELECT COUNT(*)
        FROM ${LibrarySyncDatabase._playlistSongsTable} playlist_songs
        WHERE playlist_songs.playlist_id = ${LibrarySyncDatabase._playlistsTable}.id
          AND playlist_songs.is_deleted = 0
      )
      WHERE is_deleted = 0
        AND song_count != (
          SELECT COUNT(*)
          FROM ${LibrarySyncDatabase._playlistSongsTable} playlist_songs
          WHERE playlist_songs.playlist_id = ${LibrarySyncDatabase._playlistsTable}.id
            AND playlist_songs.is_deleted = 0
        )
    ''');
  }

  Future<void> upsertPlaylistSongs(
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    for (final item in playlistSongs) {
      await db.insert(
        LibrarySyncDatabase._playlistSongsTable,
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
    final db = executor ?? await _owner.database;
    await db.delete(
      LibrarySyncDatabase._playlistSongsTable,
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await upsertPlaylistSongs(playlistSongs, executor: db);
  }

  Future<void> softDeleteAlbum(String id, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _owner.database;
    await db.update(
      LibrarySyncDatabase._albumsTable,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteSong(String id, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _owner.database;
    await db.update(
      LibrarySyncDatabase._songsTable,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeletePlaylist(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    await db.update(
      LibrarySyncDatabase._playlistsTable,
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.update(
      LibrarySyncDatabase._playlistSongsTable,
      {'is_deleted': 1},
      where: 'playlist_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeletePlaylistSong(
    String playlistId,
    int position, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    await db.update(
      LibrarySyncDatabase._playlistSongsTable,
      {'is_deleted': 1},
      where: 'playlist_id = ? AND position = ?',
      whereArgs: [playlistId, position],
    );
  }

  Future<void> softDeletePlaylistSongsBySongId(
    String playlistId,
    String songId, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    await db.update(
      LibrarySyncDatabase._playlistSongsTable,
      {'is_deleted': 1},
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
  }

  Future<void> saveSyncState(
    LibrarySyncState state, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    await db.insert(
      LibrarySyncDatabase._syncStateTable,
      {
        'id': 1,
        'last_applied_token': state.lastAppliedToken,
        'bootstrap_complete': state.bootstrapComplete ? 1 : 0,
        'last_sync_epoch_ms': state.lastSyncEpochMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertAlbumsIntoTable(
    String table,
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
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
    final db = executor ?? await _owner.database;
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
    final db = executor ?? await _owner.database;
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
