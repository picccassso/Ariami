part of 'playlist_service.dart';

extension _PlaylistServiceServerImpl on PlaylistService {
  Future<void> _autoHideMatchingServerPlaylists() async {
    if (_serverPlaylists.isEmpty || _playlists.isEmpty) return;

    final localPlaylistNames =
        _playlists.map((playlist) => playlist.name.toLowerCase()).toSet();

    var hiddenCount = 0;
    for (final serverPlaylist in _serverPlaylists) {
      final normalizedName = serverPlaylist.name.toLowerCase();
      if (localPlaylistNames.contains(normalizedName) &&
          !_hiddenServerPlaylistIds.contains(serverPlaylist.id)) {
        _hiddenServerPlaylistIds.add(serverPlaylist.id);
        hiddenCount++;
      }
    }

    if (hiddenCount > 0) {
      await _saveHiddenServerPlaylists();
      print(
        '[PlaylistService] Auto-hidden $hiddenCount server playlists by name match',
      );
    }
  }

  Future<void> _applyServerImportStateImpl({
    required Set<String> hiddenServerPlaylistIds,
    required Map<String, String> importedFromServer,
    required bool replace,
  }) async {
    if (replace) {
      _hiddenServerPlaylistIds = Set<String>.from(hiddenServerPlaylistIds);
      _importedFromServer = Map<String, String>.from(importedFromServer);
    } else {
      _hiddenServerPlaylistIds.addAll(hiddenServerPlaylistIds);
      _importedFromServer.addAll(importedFromServer);
    }

    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();
    await _autoHideMatchingServerPlaylists();
    _notifyListeners();
  }

  void _updateServerPlaylistsImpl(List<ServerPlaylist> playlists) {
    if (_serverPlaylistsEqual(_serverPlaylists, playlists)) {
      return;
    }

    _serverPlaylists = playlists;
    print('[PlaylistService] Updated server playlists: ${playlists.length}');

    _autoHideMatchingServerPlaylists().then((_) {
      _notifyListeners();
    });
  }

  bool _serverPlaylistsEqual(
    List<ServerPlaylist> current,
    List<ServerPlaylist> next,
  ) {
    if (identical(current, next)) {
      return true;
    }
    if (current.length != next.length) {
      return false;
    }

    for (var index = 0; index < current.length; index++) {
      final currentPlaylist = current[index];
      final nextPlaylist = next[index];

      if (currentPlaylist.id != nextPlaylist.id ||
          currentPlaylist.name != nextPlaylist.name ||
          currentPlaylist.songCount != nextPlaylist.songCount) {
        return false;
      }
      if (currentPlaylist.songIds.length != nextPlaylist.songIds.length) {
        return false;
      }
      for (var songIndex = 0;
          songIndex < currentPlaylist.songIds.length;
          songIndex++) {
        if (currentPlaylist.songIds[songIndex] !=
            nextPlaylist.songIds[songIndex]) {
          return false;
        }
      }
    }

    return true;
  }

  Future<void> _unhideServerPlaylistImpl(String serverPlaylistId) async {
    _hiddenServerPlaylistIds.remove(serverPlaylistId);
    await _saveHiddenServerPlaylists();
    _notifyListeners();
  }

  ServerPlaylist? _getServerPlaylistImpl(String id) {
    try {
      return _serverPlaylists.firstWhere((playlist) => playlist.id == id);
    } catch (_) {
      return null;
    }
  }
}
