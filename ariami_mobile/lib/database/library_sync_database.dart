import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

part 'library_sync_database_models.dart';
part 'library_sync_database_reads.dart';
part 'library_sync_database_schema.dart';
part 'library_sync_database_writes.dart';

/// SQLite database for normalized library sync state.
class LibrarySyncDatabase {
  static const String _databaseName = 'library_sync.db';
  static const int _databaseVersion = 5;

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

  final _LibrarySyncDatabaseSchema _schema = _LibrarySyncDatabaseSchema();
  late final _LibrarySyncDatabaseWrites _writes =
      _LibrarySyncDatabaseWrites(this);
  late final _LibrarySyncDatabaseReads _reads = _LibrarySyncDatabaseReads(this);

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

  Future<void> _onCreate(Database db, int version) {
    return _schema.onCreate(db, version);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) {
    return _schema.onUpgrade(db, oldVersion, newVersion);
  }

  Future<void> runInTransaction(
    Future<void> Function(Transaction txn) action,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await action(txn);
    });
  }

  Future<void> clearLibraryData({DatabaseExecutor? executor}) {
    return _writes.clearLibraryData(executor: executor);
  }

  Future<void> clearBootstrapStagingData({DatabaseExecutor? executor}) {
    return _writes.clearBootstrapStagingData(executor: executor);
  }

  Future<void> upsertAlbums(
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertAlbums(albums, executor: executor);
  }

  Future<void> upsertSongs(
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertSongs(songs, executor: executor);
  }

  Future<void> upsertPlaylists(
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertPlaylists(playlists, executor: executor);
  }

  Future<void> upsertBootstrapStagingAlbums(
    Iterable<LibraryAlbumRow> albums, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertBootstrapStagingAlbums(albums, executor: executor);
  }

  Future<void> upsertBootstrapStagingSongs(
    Iterable<LibrarySongRow> songs, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertBootstrapStagingSongs(songs, executor: executor);
  }

  Future<void> upsertBootstrapStagingPlaylists(
    Iterable<LibraryPlaylistRow> playlists, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertBootstrapStagingPlaylists(playlists,
        executor: executor);
  }

  Future<void> upsertBootstrapStagingPlaylistSongs(
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertBootstrapStagingPlaylistSongs(
      playlistSongs,
      executor: executor,
    );
  }

  Future<void> replacePrimaryWithBootstrapStaging({
    DatabaseExecutor? executor,
  }) {
    return _writes.replacePrimaryWithBootstrapStaging(executor: executor);
  }

  Future<void> upsertPlaylistSongs(
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) {
    return _writes.upsertPlaylistSongs(playlistSongs, executor: executor);
  }

  Future<void> replacePlaylistSongs(
    String playlistId,
    Iterable<LibraryPlaylistSongRow> playlistSongs, {
    DatabaseExecutor? executor,
  }) {
    return _writes.replacePlaylistSongs(
      playlistId,
      playlistSongs,
      executor: executor,
    );
  }

  Future<void> softDeleteAlbum(String id, {DatabaseExecutor? executor}) {
    return _writes.softDeleteAlbum(id, executor: executor);
  }

  Future<void> softDeleteSong(String id, {DatabaseExecutor? executor}) {
    return _writes.softDeleteSong(id, executor: executor);
  }

  Future<void> softDeletePlaylist(String id, {DatabaseExecutor? executor}) {
    return _writes.softDeletePlaylist(id, executor: executor);
  }

  Future<void> softDeletePlaylistSong(
    String playlistId,
    int position, {
    DatabaseExecutor? executor,
  }) {
    return _writes.softDeletePlaylistSong(
      playlistId,
      position,
      executor: executor,
    );
  }

  Future<void> softDeletePlaylistSongsBySongId(
    String playlistId,
    String songId, {
    DatabaseExecutor? executor,
  }) {
    return _writes.softDeletePlaylistSongsBySongId(
      playlistId,
      songId,
      executor: executor,
    );
  }

  Future<LibraryAlbumRow?> getAlbumById(String id) {
    return _reads.getAlbumById(id);
  }

  Future<LibrarySongRow?> getSongById(String id) {
    return _reads.getSongById(id);
  }

  Future<List<LibraryAlbumRow>> listAlbums() {
    return _reads.listAlbums();
  }

  Future<List<LibrarySongRow>> listSongs() {
    return _reads.listSongs();
  }

  Future<List<LibrarySongRow>> listSongsByAlbumId(String albumId) {
    return _reads.listSongsByAlbumId(albumId);
  }

  Future<List<LibraryPlaylistRow>> listPlaylists() {
    return _reads.listPlaylists();
  }

  Future<List<LibraryPlaylistSongRow>> listPlaylistSongs(String playlistId) {
    return _reads.listPlaylistSongs(playlistId);
  }

  Future<LibrarySyncState> getSyncState({DatabaseExecutor? executor}) {
    return _reads.getSyncState(executor: executor);
  }

  Future<bool> hasPlaylistMembershipBackfillPending({
    DatabaseExecutor? executor,
  }) {
    return _reads.hasPlaylistMembershipBackfillPending(executor: executor);
  }

  Future<bool> hasAlbumSongCountMismatch({
    DatabaseExecutor? executor,
  }) {
    return _reads.hasAlbumSongCountMismatch(executor: executor);
  }

  Future<List<AlbumSongCountIssue>> listAlbumSongCountIssues({
    int limit = 10,
    DatabaseExecutor? executor,
  }) {
    return _reads.listAlbumSongCountIssues(limit: limit, executor: executor);
  }

  Future<List<PlaylistMembershipBackfillIssue>>
      listPlaylistMembershipBackfillIssues({
    int limit = 10,
    DatabaseExecutor? executor,
  }) {
    return _reads.listPlaylistMembershipBackfillIssues(
      limit: limit,
      executor: executor,
    );
  }

  Future<void> saveSyncState(
    LibrarySyncState state, {
    DatabaseExecutor? executor,
  }) {
    return _writes.saveSyncState(state, executor: executor);
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
