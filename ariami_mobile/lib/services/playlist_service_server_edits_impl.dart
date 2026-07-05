part of 'playlist_service.dart';

extension _PlaylistServiceServerEditsImpl on PlaylistService {
  Future<void> _loadServerPlaylistEditsImpl() async {
    final connection = ConnectionService();
    final client = connection.apiClient;
    final userId = connection.userId;
    if (client == null ||
        userId == null ||
        userId.isEmpty ||
        !connection.isAuthenticated) {
      return;
    }

    final edits = await client.getPlaylistEdits();
    // A request started for one account or endpoint must never overwrite the
    // singleton service after logout, account switch, or endpoint failover.
    if (!identical(client, connection.apiClient) ||
        userId != connection.userId ||
        !connection.isAuthenticated) {
      return;
    }
    final previousEditIds = _serverPlaylistEdits.keys.toSet();
    final parsedEdits = edits.map(ServerPlaylistEdit.fromJson);
    _serverPlaylistEdits = <String, ServerPlaylistEdit>{
      for (final edit in parsedEdits) edit.playlistId: edit,
    };
    _notifyListeners();
    // Queued offline edits are replayed first so they win over overlays
    // fetched above (and are not clobbered by the inbound sync below).
    await _replayPendingImportedEditPushesImpl();
    // Overlays that disappeared were discarded on another client; imported
    // copies of those playlists must fall back to the base server order.
    await _syncImportedPlaylistsFromServerImpl(
      revertedServerPlaylistIds:
          previousEditIds.difference(_serverPlaylistEdits.keys.toSet()),
    );
  }

  ServerPlaylistEffectiveState? _resolveServerPlaylistImpl(
    String id, {
    Set<String>? liveSongIds,
  }) {
    final base = _getServerPlaylistImpl(id);
    if (base == null) return null;

    final edit = _serverPlaylistEdits[id];
    if (edit == null) {
      return ServerPlaylistEffectiveState(
        base: base,
        name: base.name,
        songIds: _filterLive(base.songIds, liveSongIds),
        hasEdit: false,
      );
    }

    final effective = _filterLive(edit.songIds, liveSongIds);
    final effectiveSet = effective.toSet();
    final baseSnapshot = edit.baseSnapshot.toSet();
    final newOnDisk = base.songIds.where((songId) {
      if (liveSongIds != null && !liveSongIds.contains(songId)) return false;
      return !baseSnapshot.contains(songId) && !effectiveSet.contains(songId);
    });

    return ServerPlaylistEffectiveState(
      base: base,
      name: edit.name ?? base.name,
      songIds: [...effective, ...newOnDisk],
      hasEdit: true,
    );
  }

  Future<void> _reorderServerPlaylistImpl({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final liveSongIds = await _currentLiveSongIds();
    final resolved = _resolveServerPlaylistImpl(
      playlistId,
      liveSongIds: liveSongIds,
    );
    if (resolved == null) return;
    if (oldIndex < 0 || oldIndex >= resolved.songIds.length) return;

    final updatedSongIds = List<String>.from(resolved.songIds);
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex > updatedSongIds.length) return;
    final songId = updatedSongIds.removeAt(oldIndex);
    updatedSongIds.insert(newIndex, songId);

    await _saveServerPlaylistEdit(
      playlistId: playlistId,
      songIds: updatedSongIds,
      name: _serverPlaylistEdits[playlistId]?.name,
    );
  }

  Future<void> _addSongToServerPlaylistImpl({
    required String playlistId,
    required String songId,
  }) async {
    final liveSongIds = await _currentLiveSongIds();
    final resolved = _resolveServerPlaylistImpl(
      playlistId,
      liveSongIds: liveSongIds,
    );
    if (resolved == null || resolved.songIds.contains(songId)) return;

    await _saveServerPlaylistEdit(
      playlistId: playlistId,
      songIds: [...resolved.songIds, songId],
      name: _serverPlaylistEdits[playlistId]?.name,
    );
  }

  Future<void> _removeSongFromServerPlaylistImpl({
    required String playlistId,
    required String songId,
  }) async {
    final liveSongIds = await _currentLiveSongIds();
    final resolved = _resolveServerPlaylistImpl(
      playlistId,
      liveSongIds: liveSongIds,
    );
    if (resolved == null || !resolved.songIds.contains(songId)) return;

    await _saveServerPlaylistEdit(
      playlistId: playlistId,
      songIds: resolved.songIds.where((id) => id != songId).toList(),
      name: _serverPlaylistEdits[playlistId]?.name,
    );
  }

  Future<void> _renameServerPlaylistImpl({
    required String playlistId,
    required String name,
  }) async {
    final liveSongIds = await _currentLiveSongIds();
    final resolved = _resolveServerPlaylistImpl(
      playlistId,
      liveSongIds: liveSongIds,
    );
    if (resolved == null) return;

    final trimmed = name.trim();
    final editName = trimmed.isEmpty || trimmed == resolved.base.name
        ? null
        : EncodingUtils.fixEncoding(trimmed) ?? trimmed;

    await _saveServerPlaylistEdit(
      playlistId: playlistId,
      songIds: resolved.songIds,
      name: editName,
    );
  }

  Future<void> _resetServerPlaylistEditImpl(String playlistId) async {
    final client = ConnectionService().apiClient;
    if (client == null || !ConnectionService().isAuthenticated) {
      return;
    }

    final previous = _serverPlaylistEdits[playlistId];
    _serverPlaylistEdits.remove(playlistId);
    _notifyListeners();

    try {
      await client.deletePlaylistEdit(playlistId);
    } catch (_) {
      if (previous != null) {
        _serverPlaylistEdits[playlistId] = previous;
        _notifyListeners();
      }
      rethrow;
    }
    await _syncImportedPlaylistsFromServerImpl(
      revertedServerPlaylistIds: {playlistId},
    );
  }

  /// Returns true when the edit reached the server, false when preconditions
  /// (connection, auth, known base playlist) were not met.
  Future<bool> _saveServerPlaylistEdit({
    required String playlistId,
    required List<String> songIds,
    required String? name,
  }) async {
    final base = _getServerPlaylistImpl(playlistId);
    final client = ConnectionService().apiClient;
    if (base == null ||
        client == null ||
        !ConnectionService().isAuthenticated) {
      return false;
    }

    final previous = _serverPlaylistEdits[playlistId];
    final edit = ServerPlaylistEdit(
      playlistId: playlistId,
      name: name,
      songIds: List<String>.from(songIds),
      baseSnapshot: List<String>.from(base.songIds),
    );

    _serverPlaylistEdits[playlistId] = edit;
    _notifyListeners();
    await _syncImportedPlaylistsFromServerImpl();

    try {
      await client.putPlaylistEdit(
        playlistId,
        songIds: edit.songIds,
        name: edit.name,
        baseSnapshot: edit.baseSnapshot,
      );
    } catch (_) {
      if (previous == null) {
        _serverPlaylistEdits.remove(playlistId);
      } else {
        _serverPlaylistEdits[playlistId] = previous;
      }
      // Imported copies are not resynced here: a failed push must not undo
      // the local edit, and the next successful edits load reconciles anyway.
      _notifyListeners();
      rethrow;
    }
    return true;
  }

  Future<Set<String>?> _currentLiveSongIds() async {
    try {
      final songs = await _libraryRepository.getSongs();
      if (songs.isEmpty) return null;
      return songs.map((song) => song.id).toSet();
    } catch (_) {
      return null;
    }
  }

  List<String> _filterLive(List<String> songIds, Set<String>? liveSongIds) {
    if (liveSongIds == null) return List<String>.from(songIds);
    return songIds.where(liveSongIds.contains).toList();
  }
}
