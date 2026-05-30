import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/api_models.dart';
import 'library/library_repository.dart';
import 'song_id_remapping_service.dart';

part 'playlist_service_local_impl.dart';
part 'playlist_service_liked_songs_impl.dart';
part 'playlist_service_backup_impl.dart';
part 'playlist_service_metadata_impl.dart';
part 'playlist_service_persistence_impl.dart';
part 'playlist_service_server_impl.dart';
part 'playlist_service_server_import_impl.dart';

/// Service for managing playlists locally.
///
/// Handles CRUD operations and persistence via SharedPreferences. It also
/// manages server playlists discovered from [PLAYLIST] folders.
class PlaylistService extends ChangeNotifier {
  static const String _storageKey = 'ariami_playlists';
  static const String _hiddenServerPlaylistsKey =
      'ariami_hidden_server_playlists';
  static const String _importedFromServerKey = 'ariami_imported_from_server';
  static const String likedSongsId = '__LIKED_SONGS__';
  static final PlaylistService _instance = PlaylistService._internal();

  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final Uuid _uuid = const Uuid();
  LibraryRepository _libraryRepository = LibraryRepository();
  List<PlaylistModel> _playlists = [];
  bool _isLoaded = false;

  // Server playlists (from API)
  List<ServerPlaylist> _serverPlaylists = [];
  Set<String> _hiddenServerPlaylistIds = {};
  // Track which local playlists were imported from server (localId -> serverId)
  Map<String, String> _importedFromServer = {};
  // Track recently imported playlists for temporary UI indicator.
  final Set<String> _recentlyImportedIds = {};

  /// Get all local playlists.
  List<PlaylistModel> get playlists => List.unmodifiable(_playlists);

  /// Get all server playlists.
  List<ServerPlaylist> get serverPlaylists =>
      List.unmodifiable(_serverPlaylists);

  /// Get visible server playlists (not hidden/imported).
  List<ServerPlaylist> get visibleServerPlaylists => _serverPlaylists
      .where((playlist) => !_hiddenServerPlaylistIds.contains(playlist.id))
      .toList();

  /// Get hidden server playlists (for recovery).
  List<ServerPlaylist> get hiddenServerPlaylists => _serverPlaylists
      .where((playlist) => _hiddenServerPlaylistIds.contains(playlist.id))
      .toList();

  /// Check if there are any visible server playlists.
  bool get hasVisibleServerPlaylists => visibleServerPlaylists.isNotEmpty;

  /// Check if there are any server playlists at all.
  bool get hasServerPlaylists => _serverPlaylists.isNotEmpty;

  /// Check if a local playlist was imported from server.
  bool isImportedFromServer(String localPlaylistId) =>
      _importedFromServer.containsKey(localPlaylistId);

  /// Check if a playlist was recently imported (for temporary UI indicator).
  bool isRecentlyImported(String localPlaylistId) =>
      _recentlyImportedIds.contains(localPlaylistId);

  /// Get the server playlist ID that a local playlist was imported from.
  String? getServerPlaylistId(String localPlaylistId) =>
      _importedFromServer[localPlaylistId];

  /// Hidden server playlist IDs (for backup serialization).
  Set<String> get hiddenServerPlaylistIds =>
      Set.unmodifiable(_hiddenServerPlaylistIds);

  /// Local-to-server playlist mapping (for backup serialization).
  Map<String, String> get importedFromServer =>
      Map.unmodifiable(_importedFromServer);

  /// Check if service has loaded data.
  bool get isLoaded => _isLoaded;

  void _notifyListeners() => notifyListeners();

  /// Load playlists from SharedPreferences.
  Future<void> loadPlaylists() => _loadPlaylistsImpl();

  /// Restore server-import tracking from a backup file.
  Future<void> applyServerImportState({
    required Set<String> hiddenServerPlaylistIds,
    required Map<String, String> importedFromServer,
    required bool replace,
  }) =>
      _applyServerImportStateImpl(
        hiddenServerPlaylistIds: hiddenServerPlaylistIds,
        importedFromServer: importedFromServer,
        replace: replace,
      );

  /// Update server playlists from API response.
  ///
  /// Called when library is fetched from server.
  void updateServerPlaylists(List<ServerPlaylist> playlists) =>
      _updateServerPlaylistsImpl(playlists);

  /// Import a server playlist as a local playlist.
  ///
  /// Creates a local copy and hides the server version.
  Future<PlaylistModel> importServerPlaylist(
    ServerPlaylist serverPlaylist, {
    required List<SongModel> allSongs,
  }) =>
      _importServerPlaylistImpl(serverPlaylist, allSongs: allSongs);

  /// Import all server playlists as local playlists.
  ///
  /// Returns the number of playlists imported.
  Future<int> importAllServerPlaylists(
    List<ServerPlaylist> serverPlaylists, {
    required List<SongModel> allSongs,
  }) =>
      _importAllServerPlaylistsImpl(serverPlaylists, allSongs: allSongs);

  /// Unhide a server playlist (make it visible again).
  Future<void> unhideServerPlaylist(String serverPlaylistId) =>
      _unhideServerPlaylistImpl(serverPlaylistId);

  /// Get a server playlist by ID.
  ServerPlaylist? getServerPlaylist(String id) => _getServerPlaylistImpl(id);

  /// Create a new playlist.
  Future<PlaylistModel> createPlaylist({
    required String name,
    String? description,
  }) =>
      _createPlaylistImpl(name: name, description: description);

  /// Get a playlist by ID.
  PlaylistModel? getPlaylist(String id) => _getPlaylistImpl(id);

  /// Update playlist name, description, and/or custom image.
  ///
  /// Use [clearCustomImage] to remove the custom image.
  Future<void> updatePlaylist({
    required String id,
    String? name,
    String? description,
    String? customImagePath,
    bool clearCustomImage = false,
  }) =>
      _updatePlaylistImpl(
        id: id,
        name: name,
        description: description,
        customImagePath: customImagePath,
        clearCustomImage: clearCustomImage,
      );

  /// Delete a playlist.
  ///
  /// For imported playlists, use [deleteImportedPlaylist] instead to handle
  /// the restore option.
  Future<void> deletePlaylist(String id) => _deletePlaylistImpl(id);

  /// Delete an imported playlist with an option to restore the server version.
  Future<void> deleteImportedPlaylist(
    String id, {
    required bool restoreServerVersion,
  }) =>
      _deleteImportedPlaylistImpl(
        id,
        restoreServerVersion: restoreServerVersion,
      );

  /// Add a song to a playlist.
  ///
  /// Stores song metadata for offline display.
  Future<void> addSongToPlaylist({
    required String playlistId,
    required String songId,
    String? albumId,
    String? title,
    String? artist,
    int? duration,
  }) =>
      _addSongToPlaylistImpl(
        playlistId: playlistId,
        songId: songId,
        albumId: albumId,
        title: title,
        artist: artist,
        duration: duration,
      );

  /// Remove a song from a playlist.
  Future<void> removeSongFromPlaylist({
    required String playlistId,
    required String songId,
  }) =>
      _removeSongFromPlaylistImpl(playlistId: playlistId, songId: songId);

  /// Reorder songs in a playlist.
  Future<void> reorderSongs({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) =>
      _reorderSongsImpl(
        playlistId: playlistId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );

  /// Get or create the Liked Songs playlist.
  Future<PlaylistModel> getLikedSongsPlaylist() => _getLikedSongsPlaylistImpl();

  /// Check if a song is liked (in Liked Songs playlist).
  bool isLikedSong(String songId) => _isLikedSongImpl(songId);

  /// Toggle a song's liked status.
  ///
  /// Pass song metadata for offline display when liking.
  Future<void> toggleLikedSong(
    String songId,
    String? albumId, {
    String? title,
    String? artist,
    int? duration,
  }) =>
      _toggleLikedSongImpl(
        songId,
        albumId,
        title: title,
        artist: artist,
        duration: duration,
      );

  /// Clear all playlists (for testing).
  Future<void> clearAll() => _clearAllImpl();

  /// Clear all local and server-derived playlist state.
  Future<void> clearAllPlaylistData() => _clearAllPlaylistDataImpl();

  /// Import playlists in merge mode, skipping existing IDs and names.
  ///
  /// Returns the number of playlists actually imported.
  Future<int> importPlaylists(List<PlaylistModel> playlists) =>
      _importPlaylistsImpl(playlists);

  /// Replace all playlists.
  ///
  /// Server-import tracking is restored separately via [applyServerImportState].
  Future<void> replaceAllPlaylists(List<PlaylistModel> playlists) =>
      _replaceAllPlaylistsImpl(playlists);

  /// Rehydrate missing album IDs for playlist songs using current library data.
  ///
  /// Returns the number of playlists updated.
  Future<int> rehydrateAlbumIdsFromLibrary(List<SongModel> librarySongs) =>
      _rehydrateAlbumIdsFromLibraryImpl(librarySongs);

  /// Rehydrate cached playlist song metadata using current library data.
  ///
  /// Returns the number of playlists updated.
  Future<int> rehydrateSongMetadataFromLibrary(List<SongModel> librarySongs) =>
      _rehydrateSongMetadataFromLibraryImpl(librarySongs);

  /// Remap stale song IDs in all playlists using current library data.
  ///
  /// This is useful when the server library has been rescanned, which changes
  /// MD5-based song IDs. Returns the number of playlists modified.
  Future<int> remapPlaylistSongIds(List<SongModel> librarySongs) =>
      _remapPlaylistSongIdsImpl(librarySongs);
}
