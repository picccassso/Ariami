import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/api_models.dart';

/// Service for managing playlists locally
/// Handles CRUD operations and persistence via SharedPreferences
/// Also manages server playlists (from [PLAYLIST] folders)
class PlaylistService extends ChangeNotifier {
  static const String _storageKey = 'ariami_playlists';
  static const String _hiddenServerPlaylistsKey = 'ariami_hidden_server_playlists';
  static const String _importedFromServerKey = 'ariami_imported_from_server';
  static const String likedSongsId = '__LIKED_SONGS__';
  static final PlaylistService _instance = PlaylistService._internal();

  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final Uuid _uuid = const Uuid();
  List<PlaylistModel> _playlists = [];
  bool _isLoaded = false;

  // Server playlists (from API)
  List<ServerPlaylist> _serverPlaylists = [];
  Set<String> _hiddenServerPlaylistIds = {};
  // Track which local playlists were imported from server (localId -> serverId)
  Map<String, String> _importedFromServer = {};
  // Track recently imported playlists for temporary UI indicator (clears after 5 seconds)
  final Set<String> _recentlyImportedIds = {};

  /// Get all local playlists
  List<PlaylistModel> get playlists => List.unmodifiable(_playlists);

  /// Get all server playlists
  List<ServerPlaylist> get serverPlaylists => List.unmodifiable(_serverPlaylists);

  /// Get visible server playlists (not hidden/imported)
  List<ServerPlaylist> get visibleServerPlaylists =>
      _serverPlaylists.where((p) => !_hiddenServerPlaylistIds.contains(p.id)).toList();

  /// Get hidden server playlists (for recovery)
  List<ServerPlaylist> get hiddenServerPlaylists =>
      _serverPlaylists.where((p) => _hiddenServerPlaylistIds.contains(p.id)).toList();

  /// Check if there are any visible server playlists
  bool get hasVisibleServerPlaylists => visibleServerPlaylists.isNotEmpty;

  /// Check if there are any server playlists at all
  bool get hasServerPlaylists => _serverPlaylists.isNotEmpty;

  /// Check if a local playlist was imported from server
  bool isImportedFromServer(String localPlaylistId) =>
      _importedFromServer.containsKey(localPlaylistId);

  /// Check if a playlist was recently imported (for temporary UI indicator)
  bool isRecentlyImported(String localPlaylistId) =>
      _recentlyImportedIds.contains(localPlaylistId);

  /// Get the server playlist ID that a local playlist was imported from
  String? getServerPlaylistId(String localPlaylistId) =>
      _importedFromServer[localPlaylistId];

  /// Check if service has loaded data
  bool get isLoaded => _isLoaded;

  /// Load playlists from SharedPreferences
  Future<void> loadPlaylists() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load local playlists
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _playlists = jsonList
            .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // Load hidden server playlist IDs
      final hiddenJson = prefs.getString(_hiddenServerPlaylistsKey);
      if (hiddenJson != null && hiddenJson.isNotEmpty) {
        final List<dynamic> hiddenList = json.decode(hiddenJson);
        _hiddenServerPlaylistIds = hiddenList.cast<String>().toSet();
      }

      // Load imported from server mapping
      final importedJson = prefs.getString(_importedFromServerKey);
      if (importedJson != null && importedJson.isNotEmpty) {
        final Map<String, dynamic> importedMap = json.decode(importedJson);
        _importedFromServer = importedMap.map((k, v) => MapEntry(k, v as String));
      }

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      print('[PlaylistService] Error loading playlists: $e');
      _playlists = [];
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Save playlists to SharedPreferences
  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _playlists.map((p) => p.toJson()).toList();
      await prefs.setString(_storageKey, json.encode(jsonList));
    } catch (e) {
      print('[PlaylistService] Error saving playlists: $e');
    }
  }

  /// Save hidden server playlist IDs to SharedPreferences
  Future<void> _saveHiddenServerPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _hiddenServerPlaylistsKey,
        json.encode(_hiddenServerPlaylistIds.toList()),
      );
    } catch (e) {
      print('[PlaylistService] Error saving hidden server playlists: $e');
    }
  }

  /// Save imported from server mapping to SharedPreferences
  Future<void> _saveImportedFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _importedFromServerKey,
        json.encode(_importedFromServer),
      );
    } catch (e) {
      print('[PlaylistService] Error saving imported from server mapping: $e');
    }
  }

  // ============================================================================
  // SERVER PLAYLIST METHODS
  // ============================================================================

  /// Update server playlists from API response
  /// Called when library is fetched from server
  void updateServerPlaylists(List<ServerPlaylist> playlists) {
    _serverPlaylists = playlists;
    print('[PlaylistService] Updated server playlists: ${playlists.length}');
    notifyListeners();
  }

  /// Import a server playlist as a local playlist
  /// Creates a local copy and hides the server version
  Future<PlaylistModel> importServerPlaylist(
    ServerPlaylist serverPlaylist, {
    required List<SongModel> allSongs,
  }) async {
    final now = DateTime.now();
    final localId = _uuid.v4();

    // Build song metadata maps from allSongs
    final songAlbumIds = <String, String>{};
    final songTitles = <String, String>{};
    final songArtists = <String, String>{};
    final songDurations = <String, int>{};

    for (final songId in serverPlaylist.songIds) {
      // Find song in allSongs list
      final song = allSongs.where((s) => s.id == songId).firstOrNull;
      if (song != null) {
        if (song.albumId != null) {
          songAlbumIds[songId] = song.albumId!;
        }
        songTitles[songId] = song.title;
        songArtists[songId] = song.artist;
        songDurations[songId] = song.duration;
      }
    }

    final playlist = PlaylistModel(
      id: localId,
      name: serverPlaylist.name,
      description: null,
      songIds: List.from(serverPlaylist.songIds),
      songAlbumIds: songAlbumIds,
      songTitles: songTitles,
      songArtists: songArtists,
      songDurations: songDurations,
      createdAt: now,
      modifiedAt: now,
    );

    // Add to local playlists
    _playlists.insert(0, playlist);

    // Hide the server playlist
    _hiddenServerPlaylistIds.add(serverPlaylist.id);

    // Track that this local playlist came from server
    _importedFromServer[localId] = serverPlaylist.id;

    // Track as recently imported for temporary UI indicator
    _recentlyImportedIds.add(localId);
    Timer(const Duration(seconds: 5), () {
      _recentlyImportedIds.remove(localId);
      notifyListeners();
    });

    // Save all changes
    await _savePlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();

    print('[PlaylistService] Imported server playlist "${serverPlaylist.name}" as local');
    notifyListeners();

    return playlist;
  }

  /// Unhide a server playlist (make it visible again)
  Future<void> unhideServerPlaylist(String serverPlaylistId) async {
    _hiddenServerPlaylistIds.remove(serverPlaylistId);
    await _saveHiddenServerPlaylists();
    notifyListeners();
  }

  /// Get a server playlist by ID
  ServerPlaylist? getServerPlaylist(String id) {
    try {
      return _serverPlaylists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Create a new playlist
  Future<PlaylistModel> createPlaylist({
    required String name,
    String? description,
  }) async {
    final now = DateTime.now();
    final playlist = PlaylistModel(
      id: _uuid.v4(),
      name: name,
      description: description,
      songIds: [],
      createdAt: now,
      modifiedAt: now,
    );

    _playlists.insert(0, playlist); // Add to beginning
    await _savePlaylists();
    notifyListeners();

    return playlist;
  }

  /// Get a playlist by ID
  PlaylistModel? getPlaylist(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Update playlist name and/or description
  Future<void> updatePlaylist({
    required String id,
    String? name,
    String? description,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final playlist = _playlists[index];
    _playlists[index] = playlist.copyWith(
      name: name ?? playlist.name,
      description: description,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    notifyListeners();
  }

  /// Delete a playlist
  /// For imported playlists, use deleteImportedPlaylist() instead to handle restore option
  Future<void> deletePlaylist(String id) async {
    // Clean up imported tracking if this was an imported playlist
    final serverPlaylistId = _importedFromServer.remove(id);
    if (serverPlaylistId != null) {
      // Permanently delete - don't restore server version
      await _saveImportedFromServer();
    }

    _playlists.removeWhere((p) => p.id == id);
    await _savePlaylists();
    notifyListeners();
  }

  /// Delete an imported playlist with option to restore server version
  /// [restoreServerVersion] - if true, unhides the original server playlist
  Future<void> deleteImportedPlaylist(String id, {required bool restoreServerVersion}) async {
    final serverPlaylistId = _importedFromServer.remove(id);

    if (serverPlaylistId != null && restoreServerVersion) {
      // Restore server version by unhiding it
      _hiddenServerPlaylistIds.remove(serverPlaylistId);
      await _saveHiddenServerPlaylists();
    }

    await _saveImportedFromServer();
    _playlists.removeWhere((p) => p.id == id);
    await _savePlaylists();
    notifyListeners();
  }

  /// Add a song to a playlist
  /// Stores song metadata (title, artist, duration) for offline display
  Future<void> addSongToPlaylist({
    required String playlistId,
    required String songId,
    String? albumId,
    String? title,
    String? artist,
    int? duration,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];

    // Don't add duplicate songs
    if (playlist.songIds.contains(songId)) return;

    final updatedSongIds = List<String>.from(playlist.songIds)..add(songId);
    final updatedSongAlbumIds = Map<String, String>.from(playlist.songAlbumIds);
    final updatedSongTitles = Map<String, String>.from(playlist.songTitles);
    final updatedSongArtists = Map<String, String>.from(playlist.songArtists);
    final updatedSongDurations = Map<String, int>.from(playlist.songDurations);

    if (albumId != null) {
      updatedSongAlbumIds[songId] = albumId;
    }
    if (title != null) {
      updatedSongTitles[songId] = title;
    }
    if (artist != null) {
      updatedSongArtists[songId] = artist;
    }
    if (duration != null) {
      updatedSongDurations[songId] = duration;
    }

    _playlists[index] = playlist.copyWith(
      songIds: updatedSongIds,
      songAlbumIds: updatedSongAlbumIds,
      songTitles: updatedSongTitles,
      songArtists: updatedSongArtists,
      songDurations: updatedSongDurations,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    notifyListeners();
  }

  /// Remove a song from a playlist
  Future<void> removeSongFromPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    final updatedSongIds = List<String>.from(playlist.songIds)..remove(songId);
    _playlists[index] = playlist.copyWith(
      songIds: updatedSongIds,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    notifyListeners();
  }

  /// Reorder songs in a playlist
  Future<void> reorderSongs({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    final updatedSongIds = List<String>.from(playlist.songIds);

    // Adjust for removal
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final songId = updatedSongIds.removeAt(oldIndex);
    updatedSongIds.insert(newIndex, songId);

    _playlists[index] = playlist.copyWith(
      songIds: updatedSongIds,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    notifyListeners();
  }

  /// Get or create the Liked Songs playlist
  Future<PlaylistModel> getLikedSongsPlaylist() async {
    // Ensure playlists are loaded
    if (!_isLoaded) {
      await loadPlaylists();
    }

    // Check if Liked Songs playlist already exists
    final existingPlaylist = getPlaylist(likedSongsId);
    if (existingPlaylist != null) {
      return existingPlaylist;
    }

    // Create Liked Songs playlist
    final now = DateTime.now();
    final likedSongsPlaylist = PlaylistModel(
      id: likedSongsId,
      name: 'Liked Songs',
      description: 'Your favorite tracks',
      songIds: [],
      createdAt: now,
      modifiedAt: now,
    );

    _playlists.insert(0, likedSongsPlaylist);
    await _savePlaylists();
    notifyListeners();

    return likedSongsPlaylist;
  }

  /// Check if a song is liked (in Liked Songs playlist)
  bool isLikedSong(String songId) {
    if (!_isLoaded) return false;

    final likedPlaylist = getPlaylist(likedSongsId);
    if (likedPlaylist == null) return false;

    return likedPlaylist.songIds.contains(songId);
  }

  /// Toggle a song's liked status
  /// Pass song metadata for offline display when liking
  Future<void> toggleLikedSong(
    String songId,
    String? albumId, {
    String? title,
    String? artist,
    int? duration,
  }) async {
    // Ensure Liked Songs playlist exists
    await getLikedSongsPlaylist();

    if (isLikedSong(songId)) {
      // Remove from Liked Songs
      await removeSongFromPlaylist(
        playlistId: likedSongsId,
        songId: songId,
      );
    } else {
      // Add to Liked Songs
      await addSongToPlaylist(
        playlistId: likedSongsId,
        songId: songId,
        albumId: albumId,
        title: title,
        artist: artist,
        duration: duration,
      );
    }
  }

  /// Clear all playlists (for testing)
  Future<void> clearAll() async {
    _playlists.clear();
    await _savePlaylists();
    notifyListeners();
  }

  /// Import playlists (merge mode - skip existing IDs)
  /// Returns the number of playlists actually imported
  Future<int> importPlaylists(List<PlaylistModel> playlists) async {
    int imported = 0;
    for (final playlist in playlists) {
      // Skip if playlist with same ID already exists
      if (getPlaylist(playlist.id) != null) continue;
      _playlists.add(playlist);
      imported++;
    }
    if (imported > 0) {
      await _savePlaylists();
      notifyListeners();
    }
    return imported;
  }

  /// Replace all playlists (replace mode)
  /// Also clears server playlist tracking to avoid orphaned data
  Future<void> replaceAllPlaylists(List<PlaylistModel> playlists) async {
    _playlists = List.from(playlists);
    _isLoaded = true;

    // Clear server playlist tracking since imported playlists may no longer exist
    _hiddenServerPlaylistIds.clear();
    _importedFromServer.clear();
    _recentlyImportedIds.clear();

    await _savePlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();
    notifyListeners();
  }
}
