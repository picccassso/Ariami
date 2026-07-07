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
      // A `created:` id marks this as a standalone playlist (no server folder
      // base) so it syncs to the user's other clients via the account-scoped
      // edit store, and so its pin resolves against the same id everywhere.
      id: newCreatedPlaylistId(),
      name: name,
      description: description,
      songIds: [],
      createdAt: now,
      modifiedAt: now,
    );

    _playlists.insert(0, playlist);
    await _savePlaylists();
    _notifyListeners();

    // Publish the new playlist to the account edit store so other devices see
    // it. Queues for replay if the server is unreachable.
    unawaited(_pushCreatedPlaylistEditImpl(playlist.id));

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
    final renamed = name != null && name != playlist.name;
    _playlists[index] = playlist.copyWith(
      name: name ?? playlist.name,
      description: description,
      customImagePath: customImagePath,
      clearCustomImagePath: clearCustomImage,
      modifiedAt: DateTime.now(),
    );

    await _savePlaylists();
    _notifyListeners();
    if (renamed) {
      unawaited(_pushImportedPlaylistEditImpl(id));
    }
    if (customImagePath != null || clearCustomImage) {
      unawaited(_pushPlaylistImageImpl(id));
    }
  }

  Future<void> _deletePlaylistImpl(String id) async {
    final serverPlaylistId = _importedFromServer.remove(id);
    if (serverPlaylistId != null) {
      await _saveImportedFromServer();
    }
    await _clearImportedEditPushPending(id);
    await _forgetPlaylistImageSync(
      id,
      serverPlaylistId ?? (isCreatedPlaylistId(id) ? id : null),
    );

    _playlists.removeWhere((playlist) => playlist.id == id);
    await _savePlaylists();
    _notifyListeners();

    // A created playlist lives only in the account edit store (no folder
    // source to fall back to), so deleting it must remove that edit for every
    // device. Best-effort: if the server call fails the edit reappears on the
    // next sync, matching the imported-playlist reset behaviour.
    if (isCreatedPlaylistId(id)) {
      _serverPlaylistEdits.remove(id);
      final client = ConnectionService().apiClient;
      if (client != null && ConnectionService().isAuthenticated) {
        try {
          await client.deletePlaylistEdit(id);
        } catch (_) {}
      }
    }
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

    await _clearImportedEditPushPending(id);
    await _forgetPlaylistImageSync(id, serverPlaylistId);
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
    unawaited(_pushImportedPlaylistEditImpl(playlistId));
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
    unawaited(_pushImportedPlaylistEditImpl(playlistId));
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
    unawaited(_pushImportedPlaylistEditImpl(playlistId));
  }
}
