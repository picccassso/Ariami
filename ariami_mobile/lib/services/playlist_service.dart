import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/api_models.dart';

/// Service for managing playlists locally
/// Handles CRUD operations and persistence via SharedPreferences
class PlaylistService extends ChangeNotifier {
  static const String _storageKey = 'ariami_playlists';
  static const String likedSongsId = '__LIKED_SONGS__';
  static final PlaylistService _instance = PlaylistService._internal();

  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final Uuid _uuid = const Uuid();
  List<PlaylistModel> _playlists = [];
  bool _isLoaded = false;

  /// Get all playlists
  List<PlaylistModel> get playlists => List.unmodifiable(_playlists);

  /// Check if service has loaded data
  bool get isLoaded => _isLoaded;

  /// Load playlists from SharedPreferences
  Future<void> loadPlaylists() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _playlists = jsonList
            .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
            .toList();
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
  Future<void> deletePlaylist(String id) async {
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
  Future<void> replaceAllPlaylists(List<PlaylistModel> playlists) async {
    _playlists = List.from(playlists);
    _isLoaded = true;
    await _savePlaylists();
    notifyListeners();
  }
}
