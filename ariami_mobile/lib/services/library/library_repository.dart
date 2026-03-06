import '../../database/library_sync_database.dart';
import '../../models/api_models.dart';
import 'package:sqflite/sqflite.dart';

class LibraryRepositoryBundle {
  const LibraryRepositoryBundle({
    required this.albums,
    required this.songs,
    required this.serverPlaylists,
  });

  final List<AlbumModel> albums;
  final List<SongModel> songs;
  final List<ServerPlaylist> serverPlaylists;
}

/// Repository for normalized local library sync storage.
class LibraryRepository {
  LibraryRepository({LibrarySyncDatabase? database})
      : _databaseFuture = database == null
            ? LibrarySyncDatabase.create()
            : Future<LibrarySyncDatabase>.value(database);

  final Future<LibrarySyncDatabase> _databaseFuture;

  Future<LibrarySyncDatabase> get _database async => _databaseFuture;

  Future<LibrarySyncState> getSyncState() async {
    return (await _database).getSyncState();
  }

  Future<bool> hasCompletedBootstrap() async {
    final syncState = await getSyncState();
    return syncState.bootstrapComplete;
  }

  Future<LibraryRepositoryBundle> getLibraryBundle() async {
    final results = await Future.wait<dynamic>([
      getAlbums(),
      getSongs(),
      getServerPlaylists(),
    ]);

    return LibraryRepositoryBundle(
      albums: results[0] as List<AlbumModel>,
      songs: results[1] as List<SongModel>,
      serverPlaylists: results[2] as List<ServerPlaylist>,
    );
  }

  Future<void> resetForBootstrap() async {
    final db = await _database;
    await db.runInTransaction((txn) async {
      await db.clearBootstrapStagingData(executor: txn);
    });
  }

  Future<void> applyBootstrapPage(V2BootstrapResponse page) async {
    final db = await _database;
    await db.runInTransaction((txn) async {
      await db.upsertBootstrapStagingAlbums(
        page.albums
            .map(
              (album) => LibraryAlbumRow(
                id: album.id,
                title: album.title,
                artist: album.artist,
                coverArt: album.coverArt,
                songCount: album.songCount,
                duration: album.duration,
              ),
            )
            .toList(),
        executor: txn,
      );
      await db.upsertBootstrapStagingSongs(
        page.songs
            .map(
              (song) => LibrarySongRow(
                id: song.id,
                title: song.title,
                artist: song.artist,
                albumId: song.albumId,
                duration: song.duration,
                trackNumber: song.trackNumber,
              ),
            )
            .toList(),
        executor: txn,
      );
      await db.upsertBootstrapStagingPlaylists(
        page.playlists
            .map(
              (playlist) => LibraryPlaylistRow(
                id: playlist.id,
                name: playlist.name,
                songCount: playlist.songCount,
                duration: playlist.duration,
              ),
            )
            .toList(),
        executor: txn,
      );
    });
  }

  Future<void> completeBootstrap({required int lastAppliedToken}) async {
    final db = await _database;
    await db.runInTransaction((txn) async {
      await db.replacePrimaryWithBootstrapStaging(executor: txn);
      await db.saveSyncState(
        LibrarySyncState(
          lastAppliedToken: lastAppliedToken,
          bootstrapComplete: true,
          lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
        executor: txn,
      );
      await db.clearBootstrapStagingData(executor: txn);
    });
  }

  Future<void> abortBootstrap() async {
    final db = await _database;
    await db.clearBootstrapStagingData();
  }

  Future<void> applyChangesResponse(V2ChangesResponse response) async {
    final db = await _database;
    await db.runInTransaction((txn) async {
      for (final event in response.events) {
        await _applyChangeEvent(db, txn, event);
      }

      final effectiveToken =
          response.toToken > 0 ? response.toToken : response.syncToken;
      await db.saveSyncState(
        LibrarySyncState(
          lastAppliedToken: effectiveToken,
          bootstrapComplete: true,
          lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
        executor: txn,
      );
    });
  }

  Future<void> updateSyncState({
    required int lastAppliedToken,
    required bool bootstrapComplete,
  }) async {
    final db = await _database;
    await db.saveSyncState(
      LibrarySyncState(
        lastAppliedToken: lastAppliedToken,
        bootstrapComplete: bootstrapComplete,
        lastSyncEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<List<AlbumModel>> getAlbums() async {
    final rows = await (await _database).listAlbums();
    return rows
        .map(
          (row) => AlbumModel(
            id: row.id,
            title: row.title,
            artist: row.artist,
            coverArt: row.coverArt,
            songCount: row.songCount,
            duration: row.duration,
          ),
        )
        .toList();
  }

  Future<AlbumModel?> getAlbumById(String albumId) async {
    final row = await (await _database).getAlbumById(albumId);
    if (row == null) return null;
    return AlbumModel(
      id: row.id,
      title: row.title,
      artist: row.artist,
      coverArt: row.coverArt,
      songCount: row.songCount,
      duration: row.duration,
    );
  }

  Future<List<SongModel>> getSongs() async {
    final rows = await (await _database).listSongs();
    return rows
        .map(
          (row) => SongModel(
            id: row.id,
            title: row.title,
            artist: row.artist,
            albumId: row.albumId,
            duration: row.duration,
            trackNumber: row.trackNumber,
          ),
        )
        .toList();
  }

  Future<SongModel?> getSongById(String songId) async {
    final row = await (await _database).getSongById(songId);
    if (row == null) return null;
    return SongModel(
      id: row.id,
      title: row.title,
      artist: row.artist,
      albumId: row.albumId,
      duration: row.duration,
      trackNumber: row.trackNumber,
    );
  }

  Future<List<SongModel>> getSongsByAlbumId(String albumId) async {
    final rows = await (await _database).listSongsByAlbumId(albumId);
    return rows
        .map(
          (row) => SongModel(
            id: row.id,
            title: row.title,
            artist: row.artist,
            albumId: row.albumId,
            duration: row.duration,
            trackNumber: row.trackNumber,
          ),
        )
        .toList();
  }

  Future<List<V2PlaylistModel>> getPlaylists() async {
    final rows = await (await _database).listPlaylists();
    return rows
        .map(
          (row) => V2PlaylistModel(
            id: row.id,
            name: row.name,
            songCount: row.songCount,
            duration: row.duration,
          ),
        )
        .toList();
  }

  Future<List<ServerPlaylist>> getServerPlaylists() async {
    final db = await _database;
    final playlistRows = await db.listPlaylists();
    final playlists = <ServerPlaylist>[];

    for (final playlistRow in playlistRows) {
      final playlistSongs = await db.listPlaylistSongs(playlistRow.id);
      final songIds = playlistSongs.map((song) => song.songId).toList();

      playlists.add(
        ServerPlaylist(
          id: playlistRow.id,
          name: playlistRow.name,
          songIds: songIds,
          songCount: playlistRow.songCount,
        ),
      );
    }

    return playlists;
  }

  Future<void> close() async {
    await (await _database).close();
  }

  Future<void> _applyChangeEvent(
    LibrarySyncDatabase database,
    DatabaseExecutor executor,
    V2ChangeEvent event,
  ) async {
    if (event.op == V2ChangeOp.delete) {
      await _applyDeleteEvent(database, executor, event);
      return;
    }
    if (event.op == V2ChangeOp.upsert) {
      await _applyUpsertEvent(database, executor, event);
    }
  }

  Future<void> _applyDeleteEvent(
    LibrarySyncDatabase database,
    DatabaseExecutor executor,
    V2ChangeEvent event,
  ) async {
    switch (event.entityType) {
      case V2EntityType.album:
        await database.softDeleteAlbum(event.entityId, executor: executor);
        return;
      case V2EntityType.song:
        await database.softDeleteSong(event.entityId, executor: executor);
        return;
      case V2EntityType.playlist:
        await database.softDeletePlaylist(event.entityId, executor: executor);
        return;
      case V2EntityType.playlistSong:
        final playlistSongIds = _playlistSongIds(event);
        if (playlistSongIds == null) return;
        await database.softDeletePlaylistSong(
          playlistSongIds.playlistId,
          playlistSongIds.songId,
          executor: executor,
        );
        return;
      case V2EntityType.artwork:
        return;
      default:
        return;
    }
  }

  Future<void> _applyUpsertEvent(
    LibrarySyncDatabase database,
    DatabaseExecutor executor,
    V2ChangeEvent event,
  ) async {
    final payload = event.payload;
    if (payload == null) return;

    switch (event.entityType) {
      case V2EntityType.album:
        final album = AlbumModel.fromJson(payload);
        await database.upsertAlbums(
          <LibraryAlbumRow>[
            LibraryAlbumRow(
              id: album.id,
              title: album.title,
              artist: album.artist,
              coverArt: album.coverArt,
              songCount: album.songCount,
              duration: album.duration,
            ),
          ],
          executor: executor,
        );
        return;
      case V2EntityType.song:
        final song = SongModel.fromJson(payload);
        await database.upsertSongs(
          <LibrarySongRow>[
            LibrarySongRow(
              id: song.id,
              title: song.title,
              artist: song.artist,
              albumId: song.albumId,
              duration: song.duration,
              trackNumber: song.trackNumber,
            ),
          ],
          executor: executor,
        );
        return;
      case V2EntityType.playlist:
        final playlist = V2PlaylistModel.fromJson(payload);
        await database.upsertPlaylists(
          <LibraryPlaylistRow>[
            LibraryPlaylistRow(
              id: playlist.id,
              name: playlist.name,
              songCount: playlist.songCount,
              duration: playlist.duration,
            ),
          ],
          executor: executor,
        );
        return;
      case V2EntityType.playlistSong:
        final playlistSongIds = _playlistSongIds(event);
        if (playlistSongIds == null) return;
        final position = _toInt(
          payload['position'] ?? payload['itemOrder'] ?? payload['item_order'],
        );
        await database.upsertPlaylistSongs(
          <LibraryPlaylistSongRow>[
            LibraryPlaylistSongRow(
              playlistId: playlistSongIds.playlistId,
              songId: playlistSongIds.songId,
              position: position,
            ),
          ],
          executor: executor,
        );
        return;
      case V2EntityType.artwork:
        return;
      default:
        return;
    }
  }

  _PlaylistSongIds? _playlistSongIds(V2ChangeEvent event) {
    final payload = event.payload;
    final payloadPlaylistId = _toStringValue(
      payload?['playlistId'] ?? payload?['playlist_id'],
    );
    final payloadSongId =
        _toStringValue(payload?['songId'] ?? payload?['song_id']);

    if (payloadPlaylistId != null && payloadSongId != null) {
      return _PlaylistSongIds(
        playlistId: payloadPlaylistId,
        songId: payloadSongId,
      );
    }

    final separatorIndex = event.entityId.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex >= event.entityId.length - 1) {
      return null;
    }
    return _PlaylistSongIds(
      playlistId: event.entityId.substring(0, separatorIndex),
      songId: event.entityId.substring(separatorIndex + 1),
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String? _toStringValue(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }
}

class _PlaylistSongIds {
  const _PlaylistSongIds({
    required this.playlistId,
    required this.songId,
  });

  final String playlistId;
  final String songId;
}
