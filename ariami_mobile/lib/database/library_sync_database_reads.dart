part of 'library_sync_database.dart';

class _LibrarySyncDatabaseReads {
  _LibrarySyncDatabaseReads(this._owner);

  final LibrarySyncDatabase _owner;

  Future<LibraryAlbumRow?> getAlbumById(String id) async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._albumsTable,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _albumFromMap(rows.first);
  }

  Future<LibrarySongRow?> getSongById(String id) async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._songsTable,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _songFromMap(rows.first);
  }

  Future<List<LibraryAlbumRow>> listAlbums() async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._albumsTable,
      where: 'is_deleted = 0',
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_albumFromMap).toList();
  }

  Future<List<LibrarySongRow>> listSongs() async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._songsTable,
      where: 'is_deleted = 0',
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_songFromMap).toList();
  }

  Future<List<LibrarySongRow>> listSongsByAlbumId(String albumId) async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._songsTable,
      where: 'album_id = ? AND is_deleted = 0',
      whereArgs: [albumId],
      orderBy: 'track_number ASC, title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_songFromMap).toList();
  }

  Future<List<LibraryPlaylistRow>> listPlaylists() async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._playlistsTable,
      where: 'is_deleted = 0',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_playlistFromMap).toList();
  }

  Future<List<LibraryPlaylistSongRow>> listPlaylistSongs(
    String playlistId,
  ) async {
    final db = await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._playlistSongsTable,
      where: 'playlist_id = ? AND is_deleted = 0',
      whereArgs: [playlistId],
      orderBy: 'position ASC, song_id ASC',
    );
    return rows.map(_playlistSongFromMap).toList();
  }

  Future<LibrarySyncState> getSyncState({DatabaseExecutor? executor}) async {
    final db = executor ?? await _owner.database;
    final rows = await db.query(
      LibrarySyncDatabase._syncStateTable,
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
    final db = executor ?? await _owner.database;
    final rows = await db.rawQuery('''
      SELECT 1
      FROM ${LibrarySyncDatabase._playlistsTable} playlists
      LEFT JOIN (
        SELECT playlist_id, COUNT(*) AS active_song_count
        FROM ${LibrarySyncDatabase._playlistSongsTable}
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

  Future<bool> hasAlbumSongCountMismatch({
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    final rows = await db.rawQuery('''
      SELECT 1
      FROM ${LibrarySyncDatabase._albumsTable} albums
      LEFT JOIN (
        SELECT album_id, COUNT(*) AS active_song_count
        FROM ${LibrarySyncDatabase._songsTable}
        WHERE is_deleted = 0 AND album_id IS NOT NULL
        GROUP BY album_id
      ) album_songs
        ON album_songs.album_id = albums.id
      WHERE albums.is_deleted = 0
        AND albums.song_count != COALESCE(album_songs.active_song_count, 0)
      LIMIT 1
    ''');
    return rows.isNotEmpty;
  }

  Future<List<AlbumSongCountIssue>> listAlbumSongCountIssues({
    int limit = 10,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    final rows = await db.rawQuery('''
      SELECT
        albums.id AS album_id,
        albums.title AS album_title,
        albums.song_count AS expected_song_count,
        COALESCE(album_songs.active_song_count, 0) AS active_song_count
      FROM ${LibrarySyncDatabase._albumsTable} albums
      LEFT JOIN (
        SELECT album_id, COUNT(*) AS active_song_count
        FROM ${LibrarySyncDatabase._songsTable}
        WHERE is_deleted = 0 AND album_id IS NOT NULL
        GROUP BY album_id
      ) album_songs
        ON album_songs.album_id = albums.id
      WHERE albums.is_deleted = 0
        AND albums.song_count != COALESCE(album_songs.active_song_count, 0)
      ORDER BY albums.title COLLATE NOCASE ASC, albums.id ASC
      LIMIT ?
    ''', <Object?>[limit]);

    return rows
        .map(
          (row) => AlbumSongCountIssue(
            albumId: row['album_id'] as String,
            albumTitle: row['album_title'] as String? ?? '',
            expectedSongCount: row['expected_song_count'] as int? ?? 0,
            activeSongCount: row['active_song_count'] as int? ?? 0,
          ),
        )
        .toList();
  }

  Future<List<PlaylistMembershipBackfillIssue>>
      listPlaylistMembershipBackfillIssues({
    int limit = 10,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _owner.database;
    final rows = await db.rawQuery('''
      SELECT
        playlists.id AS playlist_id,
        playlists.name AS playlist_name,
        playlists.song_count AS expected_song_count,
        COALESCE(playlist_songs.active_song_count, 0) AS active_song_count
      FROM ${LibrarySyncDatabase._playlistsTable} playlists
      LEFT JOIN (
        SELECT playlist_id, COUNT(*) AS active_song_count
        FROM ${LibrarySyncDatabase._playlistSongsTable}
        WHERE is_deleted = 0
        GROUP BY playlist_id
      ) playlist_songs
        ON playlist_songs.playlist_id = playlists.id
      WHERE playlists.is_deleted = 0
        AND playlists.song_count != COALESCE(playlist_songs.active_song_count, 0)
      ORDER BY playlists.name COLLATE NOCASE ASC, playlists.id ASC
      LIMIT ?
    ''', <Object?>[limit]);

    return rows
        .map(
          (row) => PlaylistMembershipBackfillIssue(
            playlistId: row['playlist_id'] as String,
            playlistName: row['playlist_name'] as String? ?? '',
            expectedSongCount: row['expected_song_count'] as int? ?? 0,
            activeSongCount: row['active_song_count'] as int? ?? 0,
          ),
        )
        .toList();
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
}
