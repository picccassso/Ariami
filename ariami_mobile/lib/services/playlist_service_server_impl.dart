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

  PlaylistModel? _findLocalPlaylistForServerId(String serverPlaylistId) {
    for (final entry in _importedFromServer.entries) {
      if (entry.value == serverPlaylistId) {
        return getPlaylist(entry.key);
      }
    }
    return null;
  }

  Future<void> _ensureServerPlaylistHidden(
    String serverPlaylistId,
    String localPlaylistId,
  ) async {
    var changed = false;
    if (!_hiddenServerPlaylistIds.contains(serverPlaylistId)) {
      _hiddenServerPlaylistIds.add(serverPlaylistId);
      changed = true;
    }
    if (_importedFromServer[localPlaylistId] != serverPlaylistId) {
      _importedFromServer[localPlaylistId] = serverPlaylistId;
      changed = true;
    }
    if (changed) {
      await _saveHiddenServerPlaylists();
      await _saveImportedFromServer();
      _notifyListeners();
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

  Future<PlaylistModel> _importServerPlaylistImpl(
    ServerPlaylist serverPlaylist, {
    required List<SongModel> allSongs,
  }) async {
    if (_hiddenServerPlaylistIds.contains(serverPlaylist.id)) {
      final existing = _findLocalPlaylistForServerId(serverPlaylist.id) ??
          _findLocalPlaylistByName(serverPlaylist.name);
      if (existing != null) {
        return existing;
      }
    }

    final existingByName = _findLocalPlaylistByName(serverPlaylist.name);
    if (existingByName != null) {
      await _ensureServerPlaylistHidden(serverPlaylist.id, existingByName.id);
      return existingByName;
    }

    final now = DateTime.now();
    final localId = _uuid.v4();
    final metadata = await _buildPlaylistSongMetadata(
      serverPlaylist.songIds,
      allSongs: allSongs,
    );

    final playlist = PlaylistModel(
      id: localId,
      name: serverPlaylist.name,
      description: null,
      songIds: List.from(serverPlaylist.songIds),
      songAlbumIds: metadata.songAlbumIds,
      songTitles: metadata.songTitles,
      songArtists: metadata.songArtists,
      songDurations: metadata.songDurations,
      createdAt: now,
      modifiedAt: now,
    );

    _playlists.insert(0, playlist);
    _hiddenServerPlaylistIds.add(serverPlaylist.id);
    _importedFromServer[localId] = serverPlaylist.id;
    _markRecentlyImported(localId);

    await _savePlaylists();
    await _saveHiddenServerPlaylists();
    await _saveImportedFromServer();

    print(
      '[PlaylistService] Imported server playlist "${serverPlaylist.name}" as local',
    );
    _notifyListeners();

    return playlist;
  }

  Future<int> _importAllServerPlaylistsImpl(
    List<ServerPlaylist> serverPlaylists, {
    required List<SongModel> allSongs,
  }) async {
    var imported = 0;
    final now = DateTime.now();
    final canonicalSongsById = await _buildCanonicalSongIndex(allSongs);

    for (final serverPlaylist in serverPlaylists) {
      if (_hiddenServerPlaylistIds.contains(serverPlaylist.id)) continue;
      if (_findLocalPlaylistByName(serverPlaylist.name) != null) continue;

      final localId = _uuid.v4();
      final metadata = _buildPlaylistSongMetadataFromIndex(
        serverPlaylist.songIds,
        canonicalSongsById,
      );

      final playlist = PlaylistModel(
        id: localId,
        name: serverPlaylist.name,
        description: null,
        songIds: List.from(serverPlaylist.songIds),
        songAlbumIds: metadata.songAlbumIds,
        songTitles: metadata.songTitles,
        songArtists: metadata.songArtists,
        songDurations: metadata.songDurations,
        createdAt: now,
        modifiedAt: now,
      );

      _playlists.insert(0, playlist);
      _hiddenServerPlaylistIds.add(serverPlaylist.id);
      _importedFromServer[localId] = serverPlaylist.id;
      _markRecentlyImported(localId);
      imported++;
    }

    if (imported > 0) {
      await _savePlaylists();
      await _saveHiddenServerPlaylists();
      await _saveImportedFromServer();
      _notifyListeners();
    }

    print('[PlaylistService] Imported $imported server playlists');
    return imported;
  }

  void _markRecentlyImported(String localId) {
    _recentlyImportedIds.add(localId);
    Timer(const Duration(seconds: 5), () {
      _recentlyImportedIds.remove(localId);
      _notifyListeners();
    });
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
