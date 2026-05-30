part of 'playlist_service.dart';

extension _PlaylistServiceLocalImpl on PlaylistService {
  PlaylistModel? _findLocalPlaylistByName(String name) {
    final normalizedName = name.toLowerCase();
    for (final playlist in _playlists) {
      if (playlist.name.toLowerCase() == normalizedName) {
        return playlist;
      }
    }
    return null;
  }

  Future<PlaylistModel> _createPlaylistImpl({
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

    _playlists.insert(0, playlist);
    await _savePlaylists();
    _notifyListeners();

    return playlist;
  }

  PlaylistModel? _getPlaylistImpl(String id) {
    try {
      return _playlists.firstWhere((playlist) => playlist.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _updatePlaylistImpl({
    required String id,
    String? name,
    String? description,
    String? customImagePath,
    bool clearCustomImage = false,
  }) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == id);
    if (index == -1) return;

    final playlist = _playlists[index];
    _playlists[index] = playlist.copyWith(
      name: name ?? playlist.name,
      description: description,
      customImagePath: customImagePath,
      clearCustomImagePath: clearCustomImage,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    _notifyListeners();
  }

  Future<void> _deletePlaylistImpl(String id) async {
    final serverPlaylistId = _importedFromServer.remove(id);
    if (serverPlaylistId != null) {
      await _saveImportedFromServer();
    }

    _playlists.removeWhere((playlist) => playlist.id == id);
    await _savePlaylists();
    _notifyListeners();
  }

  Future<void> _deleteImportedPlaylistImpl(
    String id, {
    required bool restoreServerVersion,
  }) async {
    final serverPlaylistId = _importedFromServer.remove(id);

    if (serverPlaylistId != null && restoreServerVersion) {
      _hiddenServerPlaylistIds.remove(serverPlaylistId);
      await _saveHiddenServerPlaylists();
    }

    await _saveImportedFromServer();
    _playlists.removeWhere((playlist) => playlist.id == id);
    await _savePlaylists();
    _notifyListeners();
  }

  Future<void> _addSongToPlaylistImpl({
    required String playlistId,
    required String songId,
    String? albumId,
    String? title,
    String? artist,
    int? duration,
  }) async {
    final index =
        _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
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
    _notifyListeners();
  }

  Future<void> _removeSongFromPlaylistImpl({
    required String playlistId,
    required String songId,
  }) async {
    final index =
        _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    final updatedSongIds = List<String>.from(playlist.songIds)..remove(songId);
    _playlists[index] = playlist.copyWith(
      songIds: updatedSongIds,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    _notifyListeners();
  }

  Future<void> _reorderSongsImpl({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final index =
        _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    final updatedSongIds = List<String>.from(playlist.songIds);

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
    _notifyListeners();
  }

  Future<PlaylistModel> _getLikedSongsPlaylistImpl() async {
    if (!_isLoaded) {
      await loadPlaylists();
    }

    final existingPlaylist = getPlaylist(PlaylistService.likedSongsId);
    if (existingPlaylist != null) {
      return existingPlaylist;
    }

    final now = DateTime.now();
    final likedSongsPlaylist = PlaylistModel(
      id: PlaylistService.likedSongsId,
      name: 'Liked Songs',
      description: 'Your favorite tracks',
      songIds: [],
      createdAt: now,
      modifiedAt: now,
    );

    _playlists.insert(0, likedSongsPlaylist);
    await _savePlaylists();
    _notifyListeners();

    return likedSongsPlaylist;
  }

  bool _isLikedSongImpl(String songId) {
    if (!_isLoaded) return false;

    final likedPlaylist = getPlaylist(PlaylistService.likedSongsId);
    if (likedPlaylist == null) return false;

    return likedPlaylist.songIds.contains(songId);
  }

  Future<void> _toggleLikedSongImpl(
    String songId,
    String? albumId, {
    String? title,
    String? artist,
    int? duration,
  }) async {
    await getLikedSongsPlaylist();

    if (isLikedSong(songId)) {
      await removeSongFromPlaylist(
        playlistId: PlaylistService.likedSongsId,
        songId: songId,
      );
    } else {
      await addSongToPlaylist(
        playlistId: PlaylistService.likedSongsId,
        songId: songId,
        albumId: albumId,
        title: title,
        artist: artist,
        duration: duration,
      );
    }
  }

  Future<void> _clearAllImpl() async {
    _playlists.clear();
    await _savePlaylists();
    _notifyListeners();
  }

  Future<void> _clearAllPlaylistDataImpl() async {
    _playlists.clear();
    _serverPlaylists.clear();
    _hiddenServerPlaylistIds.clear();
    _importedFromServer.clear();
    _recentlyImportedIds.clear();
    _isLoaded = true;

    await _savePlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();
    _notifyListeners();
  }

  Future<int> _importPlaylistsImpl(List<PlaylistModel> playlists) async {
    var imported = 0;
    for (final playlist in playlists) {
      if (getPlaylist(playlist.id) != null) continue;
      if (_findLocalPlaylistByName(playlist.name) != null) continue;
      _playlists.add(playlist);
      imported++;
    }
    if (imported > 0) {
      await _savePlaylists();
      await _autoHideMatchingServerPlaylists();
      _notifyListeners();
    }
    return imported;
  }

  Future<void> _replaceAllPlaylistsImpl(List<PlaylistModel> playlists) async {
    _playlists = List.from(playlists);
    _isLoaded = true;
    _recentlyImportedIds.clear();

    await _savePlaylists();
    await _autoHideMatchingServerPlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();
    _notifyListeners();
  }
}
