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

    final payload = await client.getPlaylistEditsAndImages();
    // A request started for one account or endpoint must never overwrite the
    // singleton service after logout, account switch, or endpoint failover.
    if (!identical(client, connection.apiClient) ||
        userId != connection.userId ||
        !connection.isAuthenticated) {
      return;
    }
    final previousEditIds = _serverPlaylistEdits.keys.toSet();
    final parsedEdits = payload.edits.map(ServerPlaylistEdit.fromJson);
    _serverPlaylistEdits = <String, ServerPlaylistEdit>{
      for (final edit in parsedEdits) edit.playlistId: edit,
    };
    _serverPlaylistImages = payload.images
        .map(ServerPlaylistImage.fromJson)
        .whereType<ServerPlaylistImage>()
        .toList(growable: false);
    _notifyListeners();
    // One-time migration for likes created by older mobile builds, which kept
    // Liked Songs only on-device. If the account has no synced row yet, make
    // the existing local list the initial server state instead of losing it.
    final localLiked = _getPlaylistImpl(PlaylistService.likedSongsId);
    if (!_serverPlaylistEdits.containsKey(PlaylistService.likedSongsId) &&
        localLiked != null &&
        localLiked.songIds.isNotEmpty) {
      await _markImportedEditPushPending(PlaylistService.likedSongsId);
    }
    // Queued offline edits are replayed first so they win over overlays
    // fetched above (and are not clobbered by the inbound sync below).
    await _replayPendingImportedEditPushesImpl();
    // Overlays that disappeared were discarded on another client; imported
    // copies of those playlists must fall back to the base server order.
    final removedEditIds =
        previousEditIds.difference(_serverPlaylistEdits.keys.toSet());
    await _syncImportedPlaylistsFromServerImpl(
      revertedServerPlaylistIds: removedEditIds,
    );
    // Standalone created playlists (no server folder) are materialized as
    // local copies here so they show up alongside imported playlists.
    await _syncCreatedPlaylistsFromEditsImpl(
      removedCreatedPlaylistIds:
          removedEditIds.where(isAccountOwnedPlaylistId).toSet(),
    );
    // Photos follow the same order as edits: queued local changes are
    // replayed first so they win, then the server's image manifest is
    // mirrored onto the local playlist copies.
    await _replayPendingPlaylistImagePushesImpl();
    await _applyServerPlaylistImagesImpl();
  }

  /// Materializes/updates/removes client-created playlists from the account
  /// edit store. A created playlist has no server folder base, so it lives as a
  /// local [PlaylistModel] keyed by the edit's (`created:`) playlist id — the
  /// same id used for its pin, so pins resolve locally on every device.
  Future<void> _syncCreatedPlaylistsFromEditsImpl({
    Set<String> removedCreatedPlaylistIds = const <String>{},
  }) async {
    var changed = false;

    // Remove created playlists deleted on another device (seen in a previous
    // sync, absent now). A playlist created locally but not yet synced never
    // appeared in a prior snapshot, so it is untouched by this path.
    for (final id in removedCreatedPlaylistIds) {
      if (_pendingImportedEditPushes.contains(id)) continue;
      final before = _playlists.length;
      _playlists.removeWhere((playlist) => playlist.id == id);
      if (_playlists.length != before) changed = true;
    }

    for (final entry in _serverPlaylistEdits.entries) {
      final id = entry.key;
      if (!isAccountOwnedPlaylistId(id)) continue;
      // A queued local edit is this device's newest intent; don't clobber it.
      if (_pendingImportedEditPushes.contains(id)) continue;

      final edit = entry.value;
      final name = id == likedSongsPlaylistId
          ? 'Liked Songs'
          : (edit.name != null && edit.name!.trim().isNotEmpty)
              ? edit.name!.trim()
              : 'Playlist';
      final songIds = List<String>.from(edit.songIds);
      final index = _playlists.indexWhere((playlist) => playlist.id == id);

      if (index == -1) {
        final metadata =
            await _buildPlaylistSongMetadata(songIds, allSongs: const []);
        final now = DateTime.now();
        _playlists.insert(
          0,
          PlaylistModel(
            id: id,
            name: name,
            songIds: songIds,
            songAlbumIds: metadata.songAlbumIds,
            songTitles: metadata.songTitles,
            songArtists: metadata.songArtists,
            songDurations: metadata.songDurations,
            createdAt: now,
            modifiedAt: now,
          ),
        );
        changed = true;
      } else {
        final existing = _playlists[index];
        if (existing.name != name || !listEquals(existing.songIds, songIds)) {
          final metadata =
              await _buildPlaylistSongMetadata(songIds, allSongs: const []);
          _playlists[index] = existing.copyWith(
            name: name,
            songIds: songIds,
            songAlbumIds: metadata.songAlbumIds,
            songTitles: metadata.songTitles,
            songArtists: metadata.songArtists,
            songDurations: metadata.songDurations,
            modifiedAt: DateTime.now(),
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await _savePlaylists();
      _notifyListeners();
    }
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

  /// Pushes a created playlist's authoritative state to the account edit store
  /// (empty base snapshot, no required server base). Returns true when it
  /// reached the server, false when preconditions (connection, auth) weren't
  /// met. Throws on a network/server failure so the caller can queue a retry.
  Future<bool> _saveCreatedPlaylistEdit({
    required String playlistId,
    required List<String> songIds,
    required String? name,
  }) async {
    final client = ConnectionService().apiClient;
    if (client == null || !ConnectionService().isAuthenticated) {
      return false;
    }

    final trimmed = name?.trim();
    final edit = ServerPlaylistEdit(
      playlistId: playlistId,
      name: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      songIds: List<String>.from(songIds),
      baseSnapshot: const <String>[],
    );

    _serverPlaylistEdits[playlistId] = edit;
    await client.putPlaylistEdit(
      playlistId,
      songIds: edit.songIds,
      name: edit.name,
      baseSnapshot: edit.baseSnapshot,
    );
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
