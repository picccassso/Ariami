part of 'playlist_service.dart';

extension _PlaylistServiceServerImpl on PlaylistService {
  /// Repairs server playlists that older builds hid after mistaking Ariami's
  /// account-owned Liked Songs playlist for a same-named folder playlist.
  ///
  /// The repair is tracked per server playlist ID. That makes it safe to
  /// unhide the legacy collision once without resurrecting the same playlist
  /// if the user later imports and permanently deletes it intentionally.
  Future<void> _repairLikedSongsNameCollisions() async {
    final collisions = _serverPlaylists.where(
      (playlist) => playlist.name.trim().toLowerCase() == 'liked songs',
    );
    if (collisions.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final repairedIds = <String>{};
    final raw = prefs.getString(PlaylistService._likedSongsCollisionRepairKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        repairedIds.addAll((json.decode(raw) as List<dynamic>).cast<String>());
      } catch (_) {
        // A corrupt migration marker should not keep a hidden playlist lost.
      }
    }

    var hiddenChanged = false;
    var importedChanged = false;
    var markerChanged = false;
    for (final serverPlaylist in collisions) {
      final firstRepair = repairedIds.add(serverPlaylist.id);
      if (firstRepair) markerChanged = true;

      final hasRealImportedCopy = _importedFromServer.entries.any(
        (entry) =>
            entry.key != PlaylistService.likedSongsId &&
            entry.value == serverPlaylist.id &&
            _getPlaylistImpl(entry.key) != null,
      );
      var removedInvalidLikedMapping = false;
      if (_importedFromServer[PlaylistService.likedSongsId] ==
          serverPlaylist.id) {
        _importedFromServer.remove(PlaylistService.likedSongsId);
        importedChanged = true;
        removedInvalidLikedMapping = true;
      }
      if ((firstRepair || removedInvalidLikedMapping) &&
          !hasRealImportedCopy &&
          _hiddenServerPlaylistIds.remove(serverPlaylist.id)) {
        hiddenChanged = true;
      }
    }

    if (hiddenChanged) await _saveHiddenServerPlaylists();
    if (importedChanged) await _saveImportedFromServer();
    if (markerChanged) {
      await prefs.setString(
        PlaylistService._likedSongsCollisionRepairKey,
        json.encode(repairedIds.toList()),
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
    await _repairLikedSongsNameCollisions();
    _notifyListeners();
  }

  void _updateServerPlaylistsImpl(List<ServerPlaylist> playlists) {
    if (_serverPlaylistsEqual(_serverPlaylists, playlists)) {
      return;
    }

    _serverPlaylists = playlists;
    print('[PlaylistService] Updated server playlists: ${playlists.length}');

    _repairLikedSongsNameCollisions().then((_) async {
      // Edits queued while the base playlist was unknown can be pushed now.
      await _replayPendingImportedEditPushesImpl();
      await _syncImportedPlaylistsFromServerImpl();
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
