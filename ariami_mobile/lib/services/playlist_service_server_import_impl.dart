part of 'playlist_service.dart';

extension _PlaylistServiceServerImportImpl on PlaylistService {
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

    // Pick up the server playlist's synced cover photo, if it has one.
    unawaited(_applyServerPlaylistImagesImpl());

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
      // Pick up synced cover photos for the newly imported copies.
      unawaited(_applyServerPlaylistImagesImpl());
    }

    print('[PlaylistService] Imported $imported server playlists');
    return imported;
  }

  /// Mirror imported local playlists from the effective server state.
  ///
  /// Only playlists whose server counterpart has an account edit overlay are
  /// touched: an imported copy that was never edited on any client stays a
  /// local fork, and a missing overlay during startup (edits not loaded yet)
  /// cannot clobber local state. [revertedServerPlaylistIds] forces specific
  /// playlists back to the base server order after an overlay was discarded.
  Future<void> _syncImportedPlaylistsFromServerImpl({
    Set<String> revertedServerPlaylistIds = const <String>{},
  }) async {
    if (_importedFromServer.isEmpty || _serverPlaylists.isEmpty) return;

    var changed = false;
    for (final entry in _importedFromServer.entries.toList()) {
      // A queued offline edit is this device's latest intent for the
      // playlist; keep it until the replay pushes it to the server.
      if (_pendingImportedEditPushes.contains(entry.key)) continue;

      final localIndex =
          _playlists.indexWhere((playlist) => playlist.id == entry.key);
      if (localIndex == -1) continue;

      final resolved = _resolveServerPlaylistImpl(entry.value);
      if (resolved == null) continue;
      if (!resolved.hasEdit &&
          !revertedServerPlaylistIds.contains(entry.value)) {
        continue;
      }

      final playlist = _playlists[localIndex];
      if (playlist.name == resolved.name &&
          listEquals(playlist.songIds, resolved.songIds)) {
        continue;
      }

      var updated = playlist.copyWith(
        name: resolved.name,
        songIds: List<String>.from(resolved.songIds),
        modifiedAt: DateTime.now(),
      );

      final missingMetadataIds = resolved.songIds
          .where((id) => !playlist.songTitles.containsKey(id))
          .toList();
      if (missingMetadataIds.isNotEmpty) {
        final metadata = await _buildPlaylistSongMetadata(
          missingMetadataIds,
          allSongs: const <SongModel>[],
        );
        updated = updated.copyWith(
          songAlbumIds: {...playlist.songAlbumIds, ...metadata.songAlbumIds},
          songTitles: {...playlist.songTitles, ...metadata.songTitles},
          songArtists: {...playlist.songArtists, ...metadata.songArtists},
          songDurations: {
            ...playlist.songDurations,
            ...metadata.songDurations,
          },
        );
      }

      _playlists[localIndex] = updated;
      changed = true;
    }

    if (changed) {
      await _savePlaylists();
      _notifyListeners();
    }
  }

  /// Push a locally edited imported playlist to the account's server edit
  /// overlay so the change syncs to the other clients.
  ///
  /// When the push cannot reach the server (offline, logged out, base
  /// playlist not loaded yet, request failure) the playlist is queued and
  /// replayed by [_replayPendingImportedEditPushesImpl] on the next
  /// connection; until then inbound sync leaves it untouched.
  Future<void> _pushImportedPlaylistEditImpl(String localPlaylistId) async {
    // Created playlists have no server folder base; they push their own edit.
    if (isCreatedPlaylistId(localPlaylistId)) {
      await _pushCreatedPlaylistEditImpl(localPlaylistId);
      return;
    }
    final serverPlaylistId = _importedFromServer[localPlaylistId];
    final playlist = _getPlaylistImpl(localPlaylistId);
    if (serverPlaylistId == null || playlist == null) return;

    final base = _getServerPlaylistImpl(serverPlaylistId);
    if (base == null) {
      await _markImportedEditPushPending(localPlaylistId);
      return;
    }

    try {
      final pushed = await _saveServerPlaylistEdit(
        playlistId: serverPlaylistId,
        songIds: List<String>.from(playlist.songIds),
        name: playlist.name == base.name ? null : playlist.name,
      );
      if (pushed) {
        await _clearImportedEditPushPending(localPlaylistId);
      } else {
        await _markImportedEditPushPending(localPlaylistId);
      }
    } catch (error) {
      await _markImportedEditPushPending(localPlaylistId);
      debugPrint(
        '[PlaylistService] Queued imported playlist edit after failed push: '
        '$error',
      );
    }
  }

  /// Pushes a client-created playlist to the account edit store. Unlike
  /// imported playlists there is no server folder base, so the edit carries an
  /// empty base snapshot and its own name. Queues for replay on failure.
  Future<void> _pushCreatedPlaylistEditImpl(String localPlaylistId) async {
    final playlist = _getPlaylistImpl(localPlaylistId);
    if (playlist == null) return;

    try {
      final pushed = await _saveCreatedPlaylistEdit(
        playlistId: localPlaylistId,
        songIds: List<String>.from(playlist.songIds),
        name: playlist.name,
      );
      if (pushed) {
        await _clearImportedEditPushPending(localPlaylistId);
      } else {
        await _markImportedEditPushPending(localPlaylistId);
      }
    } catch (error) {
      await _markImportedEditPushPending(localPlaylistId);
      debugPrint(
        '[PlaylistService] Queued created playlist edit after failed push: '
        '$error',
      );
    }
  }

  /// Replay queued offline edits of imported playlists to the server.
  ///
  /// Last writer wins: a queued edit overwrites an overlay another client
  /// saved while this device was offline.
  Future<void> _replayPendingImportedEditPushesImpl() async {
    if (_pendingImportedEditPushes.isEmpty || _isReplayingPendingEditPushes) {
      return;
    }
    final connection = ConnectionService();
    if (connection.apiClient == null || !connection.isAuthenticated) return;

    _isReplayingPendingEditPushes = true;
    try {
      for (final localId in _pendingImportedEditPushes.toList()) {
        final stillPresent = _getPlaylistImpl(localId) != null &&
            (isCreatedPlaylistId(localId) ||
                _importedFromServer.containsKey(localId));
        if (!stillPresent) {
          // The playlist was deleted or unlinked while the push was queued.
          await _clearImportedEditPushPending(localId);
          continue;
        }
        await _pushImportedPlaylistEditImpl(localId);
      }
    } finally {
      _isReplayingPendingEditPushes = false;
    }
  }

  Future<void> _markImportedEditPushPending(String localPlaylistId) async {
    if (_pendingImportedEditPushes.add(localPlaylistId)) {
      await _savePendingImportedEditPushes();
    }
  }

  Future<void> _clearImportedEditPushPending(String localPlaylistId) async {
    if (_pendingImportedEditPushes.remove(localPlaylistId)) {
      await _savePendingImportedEditPushes();
    }
  }

  void _markRecentlyImported(String localId) {
    _recentlyImportedIds.add(localId);
    Timer(const Duration(seconds: 5), () {
      _recentlyImportedIds.remove(localId);
      _notifyListeners();
    });
  }
}
