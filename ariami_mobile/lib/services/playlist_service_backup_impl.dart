part of 'playlist_service.dart';

extension _PlaylistServiceBackupImpl on PlaylistService {
  Future<void> _clearAllImpl() async {
    _playlists.clear();
    await _savePlaylists();
    _notifyListeners();
  }

  Future<void> _clearAllPlaylistDataImpl() async {
    _playlists.clear();
    _serverPlaylists.clear();
    _serverPlaylistEdits.clear();
    _hiddenServerPlaylistIds.clear();
    _importedFromServer.clear();
    _recentlyImportedIds.clear();
    _pendingImportedEditPushes.clear();
    _serverPlaylistImages = [];
    _syncedPlaylistImageVersions.clear();
    _pendingPlaylistImagePushes.clear();
    _isLoaded = true;

    await _savePlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();
    await _savePendingImportedEditPushes();
    await _saveSyncedPlaylistImageVersions();
    await _savePendingPlaylistImagePushes();
    _notifyListeners();
  }

  Future<int> _importPlaylistsImpl(List<PlaylistModel> playlists) async {
    var imported = 0;
    for (final playlist in playlists) {
      if (getPlaylist(playlist.id) != null) continue;
      _playlists.add(playlist);
      imported++;
    }
    if (imported > 0) {
      await _savePlaylists();
      _notifyListeners();
    }
    return imported;
  }

  Future<void> _replaceAllPlaylistsImpl(List<PlaylistModel> playlists) async {
    _playlists = List.from(playlists);
    _isLoaded = true;
    _recentlyImportedIds.clear();

    await _savePlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();
    _notifyListeners();
  }
}
