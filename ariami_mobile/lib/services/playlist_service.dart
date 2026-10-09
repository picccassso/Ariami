import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/api_models.dart';
import '../utils/encoding_utils.dart';
import 'api/api_client.dart' show ApiException;
import 'api/connection_service.dart';
import 'library/library_repository.dart';
import 'song_id_remapping_service.dart';

part 'playlist_service_local_impl.dart';
part 'playlist_service_liked_songs_impl.dart';
part 'playlist_service_backup_impl.dart';
part 'playlist_service_metadata_impl.dart';
part 'playlist_service_persistence_impl.dart';
part 'playlist_service_server_impl.dart';
part 'playlist_service_server_edits_impl.dart';
part 'playlist_service_server_import_impl.dart';
part 'playlist_service_image_sync_impl.dart';

class ServerPlaylistEffectiveState {
  final ServerPlaylist base;
  final String name;
  final List<String> songIds;
  final bool hasEdit;

  const ServerPlaylistEffectiveState({
    required this.base,
    required this.name,
    required this.songIds,
    required this.hasEdit,
  });
}

/// Service for managing playlists locally.
///
/// Handles CRUD operations and persistence via SharedPreferences. It also
/// manages server playlists discovered from [PLAYLIST] folders.
class PlaylistService extends ChangeNotifier {
  static const String _storageKey = 'ariami_playlists';
  static const String _hiddenServerPlaylistsKey =
      'ariami_hidden_server_playlists';
  static const String _importedFromServerKey = 'ariami_imported_from_server';
  static const String _pendingImportedEditPushesKey =
      'ariami_pending_imported_edit_pushes';
  static const String _syncedPlaylistImageVersionsKey =
      'ariami_playlist_image_versions';
  static const String _pendingPlaylistImagePushesKey =
      'ariami_pending_playlist_image_pushes';
  static const String _likedSongsCollisionRepairKey =
      'ariami_liked_songs_collision_repair_v1';
  static const String likedSongsId = likedSongsPlaylistId;
  static final PlaylistService _instance = PlaylistService._internal();

  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final Uuid _uuid = const Uuid();
  LibraryRepository _libraryRepository = LibraryRepository();
  List<PlaylistModel> _playlists = [];
  bool _isLoaded = false;

  List<ServerPlaylist> _serverPlaylists = [];
  Map<String, ServerPlaylistEdit> _serverPlaylistEdits = {};
  Future<void>? _serverPlaylistEditsLoad;
  Set<String> _hiddenServerPlaylistIds = {};
  // Track which local playlists were imported from server (localId -> serverId)
  Map<String, String> _importedFromServer = {};
  // Imported playlists edited while the server was unreachable; their edits
  // are replayed on the next connection and shield them from inbound sync.
  Set<String> _pendingImportedEditPushes = {};
  bool _isReplayingPendingEditPushes = false;
  // Custom cover photo sync state. The manifest is the server's last-known
  // image list; versions record which image updatedAt each synced photo file
  // came from (keyed by server-side sync id); pending pushes (localId ->
  // 'put'|'delete') replay offline photo changes and shield those playlists
  // from inbound photo sync.
  List<ServerPlaylistImage> _serverPlaylistImages = [];
  Map<String, int> _syncedPlaylistImageVersions = {};
  Map<String, String> _pendingPlaylistImagePushes = {};
  bool _isReplayingPendingImagePushes = false;
  final Set<String> _recentlyImportedIds = {};

  List<PlaylistModel> get playlists => List.unmodifiable(_playlists);

  List<ServerPlaylist> get serverPlaylists =>
      List.unmodifiable(_serverPlaylists);

  Map<String, ServerPlaylistEdit> get serverPlaylistEdits =>
      Map.unmodifiable(_serverPlaylistEdits);

  /// Get visible server playlists (not hidden/imported).
  ///
  /// Account edits are applied here so every mobile surface (including the
  /// server-playlist sheet and imports) sees the same name, membership, and
  /// ordering as the detail screen and the other clients.
  List<ServerPlaylist> get visibleServerPlaylists => <ServerPlaylist>[
        for (final playlist in _serverPlaylists)
          if (!_hiddenServerPlaylistIds.contains(playlist.id))
            _effectiveServerPlaylist(playlist),
      ];

  List<ServerPlaylist> get hiddenServerPlaylists => _serverPlaylists
      .where((playlist) => _hiddenServerPlaylistIds.contains(playlist.id))
      .toList();

  bool get hasVisibleServerPlaylists => visibleServerPlaylists.isNotEmpty;

  bool get hasServerPlaylists => _serverPlaylists.isNotEmpty;

  bool isImportedFromServer(String localPlaylistId) =>
      _importedFromServer.containsKey(localPlaylistId);

  bool isRecentlyImported(String localPlaylistId) =>
      _recentlyImportedIds.contains(localPlaylistId);

  String? getServerPlaylistId(String localPlaylistId) =>
      _importedFromServer[localPlaylistId];

  /// Whether an imported local playlist's original server playlist is absent.
  bool isImportedServerPlaylistMissing(String localPlaylistId) {
    final serverPlaylistId = _importedFromServer[localPlaylistId];
    if (serverPlaylistId == null) return false;
    return !_serverPlaylists.any((playlist) => playlist.id == serverPlaylistId);
  }

  /// Hidden server playlist IDs (for backup serialization).
  Set<String> get hiddenServerPlaylistIds =>
      Set.unmodifiable(_hiddenServerPlaylistIds);

  /// Local-to-server playlist mapping (for backup serialization).
  Map<String, String> get importedFromServer =>
      Map.unmodifiable(_importedFromServer);

  /// Local IDs of imported playlists with edits not yet pushed to the server.
  Set<String> get pendingImportedEditPushIds =>
      Set.unmodifiable(_pendingImportedEditPushes);

  bool get isLoaded => _isLoaded;

  void _notifyListeners() => notifyListeners();

  Future<void> loadPlaylists() => _loadPlaylistsImpl();

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

  Future<int> importAllServerPlaylists(
    List<ServerPlaylist> serverPlaylists, {
    required List<SongModel> allSongs,
  }) =>
      _importAllServerPlaylistsImpl(serverPlaylists, allSongs: allSongs);

  ServerPlaylist? getServerPlaylist(String id) => _getServerPlaylistImpl(id);

  Future<void> loadServerPlaylistEdits() {
    final inFlight = _serverPlaylistEditsLoad;
    if (inFlight != null) return inFlight;

    final load = _loadServerPlaylistEditsImpl();
    _serverPlaylistEditsLoad = load;
    return load.whenComplete(() {
      if (identical(_serverPlaylistEditsLoad, load)) {
        _serverPlaylistEditsLoad = null;
      }
    });
  }

  /// Mirror imported local playlists from the effective server state.
  ///
  /// Runs automatically whenever server playlists or edit overlays change;
  /// exposed for callers (and tests) that need an explicit reconcile.
  Future<void> syncImportedPlaylistsFromServer({
    Set<String> revertedServerPlaylistIds = const <String>{},
  }) =>
      _syncImportedPlaylistsFromServerImpl(
        revertedServerPlaylistIds: revertedServerPlaylistIds,
      );

  ServerPlaylistEffectiveState? resolveServerPlaylist(
    String id, {
    Set<String>? liveSongIds,
  }) =>
      _resolveServerPlaylistImpl(id, liveSongIds: liveSongIds);

  ServerPlaylist _effectiveServerPlaylist(ServerPlaylist playlist) {
    final resolved = resolveServerPlaylist(playlist.id);
    if (resolved == null || !resolved.hasEdit) return playlist;
    return ServerPlaylist(
      id: playlist.id,
      name: resolved.name,
      songIds: resolved.songIds,
      songCount: resolved.songIds.length,
    );
  }

  @visibleForTesting
  void setServerPlaylistEditsForTest(List<ServerPlaylistEdit> edits) {
    _serverPlaylistEdits = <String, ServerPlaylistEdit>{
      for (final edit in edits) edit.playlistId: edit,
    };
  }

  Future<void> reorderServerPlaylist({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) =>
      _reorderServerPlaylistImpl(
        playlistId: playlistId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );

  Future<void> addSongToServerPlaylist({
    required String playlistId,
    required String songId,
  }) =>
      _addSongToServerPlaylistImpl(playlistId: playlistId, songId: songId);

  Future<void> removeSongFromServerPlaylist({
    required String playlistId,
    required String songId,
  }) =>
      _removeSongFromServerPlaylistImpl(playlistId: playlistId, songId: songId);

  Future<void> renameServerPlaylist({
    required String playlistId,
    required String name,
  }) =>
      _renameServerPlaylistImpl(playlistId: playlistId, name: name);

  Future<void> resetServerPlaylistEdit(String playlistId) =>
      _resetServerPlaylistEditImpl(playlistId);

  /// Put a server playlist back to a state captured with
  /// [resolveServerPlaylist], e.g. to undo a removal or discarded edits.
  Future<void> restoreServerPlaylist(ServerPlaylistEffectiveState snapshot) =>
      _restoreServerPlaylistImpl(snapshot);

  Future<PlaylistModel> createPlaylist({
    required String name,
    String? description,
  }) =>
      _createPlaylistImpl(name: name, description: description);

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

  Future<void> removeSongFromPlaylist({
    required String playlistId,
    required String songId,
  }) =>
      _removeSongFromPlaylistImpl(playlistId: playlistId, songId: songId);

  /// Put a playlist's songs back to an earlier order, e.g. to undo a removal.
  Future<void> restorePlaylistSongs(String playlistId, List<String> songIds) =>
      _setPlaylistSongIdsImpl(playlistId, songIds);

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

  Future<PlaylistModel> getLikedSongsPlaylist() => _getLikedSongsPlaylistImpl();

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

  Future<void> clearAllPlaylistData() => _clearAllPlaylistDataImpl();

  /// Import playlists in merge mode, skipping existing IDs.
  ///
  /// Display names are not identities: two legitimate playlists may share a
  /// name, including a server/imported playlist named "Liked Songs" alongside
  /// Ariami's account-owned likes playlist.
  ///
  /// Returns the number of playlists actually imported.
  Future<int> importPlaylists(List<PlaylistModel> playlists) =>
      _importPlaylistsImpl(playlists);

  /// Replace all playlists.
  ///
  /// Server-import tracking is restored separately via [applyServerImportState].
  Future<void> replaceAllPlaylists(List<PlaylistModel> playlists) =>
      _replaceAllPlaylistsImpl(playlists);

  Future<int> rehydrateSongMetadataFromLibrary(List<SongModel> librarySongs) =>
      _rehydrateSongMetadataFromLibraryImpl(librarySongs);

  /// Remap stale song IDs in all playlists using current library data.
  ///
  /// This is useful when the server library has been rescanned, which changes
  /// MD5-based song IDs. Returns the number of playlists modified.
  Future<int> remapPlaylistSongIds(List<SongModel> librarySongs) =>
      _remapPlaylistSongIdsImpl(librarySongs);

  /// Counts playlist entries that can never resolve — ids absent from
  /// [librarySongs] and not in [downloadedSongIds] — without mutating
  /// anything. Runs the id-remap pass first so entries that can heal by
  /// metadata match are not counted. Returns zero counts when the library
  /// list is empty (an unsynced library must never look like mass deletion).
  Future<UnavailableSongCleanupReport> previewUnavailableSongCleanup({
    required List<SongModel> librarySongs,
    required Set<String> downloadedSongIds,
  }) =>
      _previewUnavailableSongCleanupImpl(
        librarySongs: librarySongs,
        downloadedSongIds: downloadedSongIds,
      );

  /// Removes the entries [previewUnavailableSongCleanup] counts from every
  /// local playlist (including Liked Songs and imported copies; imported
  /// playlists push the edit to the server). Returns what was removed.
  Future<UnavailableSongCleanupReport> removeUnavailableSongs({
    required List<SongModel> librarySongs,
    required Set<String> downloadedSongIds,
  }) =>
      _removeUnavailableSongsImpl(
        librarySongs: librarySongs,
        downloadedSongIds: downloadedSongIds,
      );
}

class UnavailableSongCleanupReport {
  final int playlistCount;
  final int songCount;

  const UnavailableSongCleanupReport({
    required this.playlistCount,
    required this.songCount,
  });

  bool get isEmpty => songCount == 0;
}
