part of '../library_controller.dart';

extension _LibraryControllerPlaylists on LibraryController {
  Future<void> _toggleAlbumPin(String albumId) async {
    await _togglePin('album:$albumId');
  }

  Future<void> _togglePlaylistPin(String playlistId) async {
    await _togglePin('playlist:$playlistId');
  }

  Future<void> _refreshPins() async {
    final client = _client;
    if (client == null) return;
    final results = await Future.wait([
      client.fetchPins(),
      client.fetchPlaylistEditsAndImages(),
    ]);
    if (!identical(client, _client)) return;
    final editsPayload = results[1] as ({
      List<PlaylistEdit> edits,
      Map<String, int> imageVersions
    });
    _applyPlaylistImageVersions(editsPayload.imageVersions);
    _applyPlaylistEdits(editsPayload.edits);
    _applyPins(results[0] as List<PinnedMediaItem>);
    _sortLibrary();
    _notifyListeners();
  }

  Future<void> _refreshPlaylistEdits() async {
    final client = _client;
    if (client == null) return;
    final editsPayload = await client.fetchPlaylistEditsAndImages();
    if (!identical(client, _client)) return;
    _applyPlaylistImageVersions(editsPayload.imageVersions);
    _applyPlaylistEdits(editsPayload.edits);
    await _replayPendingPlaylistEdits(client);
    _sortLibrary();
    _notifyListeners();
  }

  void _applyPlaylistImageVersions(Map<String, int> imageVersions) {
    _playlistImageVersions
      ..clear()
      ..addAll(imageVersions);
  }

  /// Uploads a custom cover photo for a playlist to the account's image
  /// store. The local manifest version is bumped from the server's response
  /// so this client updates immediately; other clients pick it up via the
  /// playlistEditsChanged broadcast.
  Future<void> _setPlaylistImage(
    String playlistId, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    final client = _client;
    if (client == null) {
      throw PlayerApiException('NOT_CONNECTED', 'Not connected to a server.');
    }
    final updatedAt = await client.putPlaylistImage(
      playlistId,
      bytes: bytes,
      contentType: contentType,
    );
    _playlistImageVersions[playlistId] =
        updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    _notifyListeners();
  }

  /// Removes a playlist's custom cover photo, reverting all clients to the
  /// song-artwork mosaic.
  Future<void> _removePlaylistImage(String playlistId) async {
    final client = _client;
    if (client == null) {
      throw PlayerApiException('NOT_CONNECTED', 'Not connected to a server.');
    }
    await client.deletePlaylistImage(playlistId);
    _playlistImageVersions.remove(playlistId);
    _notifyListeners();
  }

  /// Creates a new playlist owned by this client. Returns its id, or null if
  /// the name was blank or there is no connected server. Optimistically shows
  /// the playlist immediately; a failed sync rolls it back.
  Future<String?> _createPlaylist(
    String name, {
    List<String> initialSongIds = const <String>[],
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _client == null) return null;
    final id = _newCreatedPlaylistId();
    await _putPlaylistEditOptimistically(
      id,
      songIds: initialSongIds,
      name: trimmed,
    );
    // The optimistic put rolls the edit back out on failure, so its presence
    // tells us whether creation actually stuck.
    return _playlistEdits.containsKey(id) ? id : null;
  }

  Future<void> _renamePlaylist(String playlistId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final playlist = _playlistById(playlistId);
    if (playlist == null) return;
    await _putPlaylistEditOptimistically(
      playlistId,
      songIds: playlist.songIds,
      name: trimmed,
    );
  }

  Future<void> _removeTrackFromPlaylist(
    String playlistId,
    String songId,
  ) async {
    await _updatePlaylistSongs(playlistId, (songIds) {
      songIds.remove(songId);
      return songIds;
    });
  }

  Future<void> _addTrackToPlaylist(String playlistId, String songId) async {
    await _updatePlaylistSongs(playlistId, (songIds) {
      if (!songIds.contains(songId)) songIds.add(songId);
      return songIds;
    });
  }

  /// Appends every id not already present, in the given order, as a single
  /// edit — a batch add must not cost one write (and one sync) per song.
  Future<void> _addTracksToPlaylist(
    String playlistId,
    List<String> songIds,
  ) async {
    await _updatePlaylistSongs(playlistId, (current) {
      final present = current.toSet();
      for (final id in songIds) {
        if (present.add(id)) current.add(id);
      }
      return current;
    });
  }

  Future<void> _removeTracksFromPlaylist(
    String playlistId,
    List<String> songIds,
  ) async {
    final remove = songIds.toSet();
    await _updatePlaylistSongs(
      playlistId,
      (current) => current..removeWhere(remove.contains),
    );
  }

  bool _isLikedSong(String songId) =>
      _playlistEdits[likedSongsPlaylistId]?.songIds.contains(songId) ?? false;

  /// Toggles a like locally first, then syncs it through the playlist-edit
  /// API. Failed/offline writes stay queued in the account snapshot and are
  /// replayed on reconnect.
  Future<void> _toggleLikedSong(Track track) async {
    final current = List<String>.from(
      _playlistEdits[likedSongsPlaylistId]?.songIds ?? const <String>[],
    );
    if (!current.remove(track.id)) current.add(track.id);
    await _putPlaylistEditOptimistically(
      likedSongsPlaylistId,
      songIds: current,
      name: 'Liked Songs',
    );
  }

  /// Replays durable offline playlist edits once the existing client becomes
  /// reachable again (manual offline mode keeps the same client attached).
  Future<void> _syncPendingPlaylistEdits() async {
    final client = _client;
    if (client == null) return;
    await _replayPendingPlaylistEdits(client);
  }

  Future<void> _movePlaylistTrack(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await _updatePlaylistSongs(playlistId, (songIds) {
      if (oldIndex < 0 || oldIndex >= songIds.length) return songIds;
      // newIndex comes from ReorderableList's onReorderItem, which already
      // accounts for the item removed at oldIndex — insert at it directly.
      final target = newIndex.clamp(0, songIds.length - 1);
      if (target == oldIndex) return songIds;
      final id = songIds.removeAt(oldIndex);
      songIds.insert(target, id);
      return songIds;
    });
  }

  /// Applies a "reorder via search" result in one edit: [pickedIds] become
  /// the first positions at [startIndex] (in pick order); earlier songs stay
  /// fixed and every unpicked song keeps its relative order after them.
  Future<void> _applyPlaylistPickOrder(
    String playlistId,
    List<String> pickedIds, {
    int startIndex = 0,
  }) async {
    await _updatePlaylistSongs(
      playlistId,
      (songIds) => mergePickOrder(
        songIds,
        pickedIds,
        startIndex: startIndex,
      ),
    );
  }

  /// Hides a server playlist from this desktop library. The source playlist
  /// file remains untouched, just like mobile's imported-local editing model.
  ///
  /// Client-created playlists have no source file, so they are deleted outright
  /// (locally and from the account-scoped edit store) rather than hidden.
  Future<void> _deletePlaylist(String playlistId) async {
    if (_isCreatedPlaylistId(playlistId)) {
      await _deleteCreatedPlaylist(playlistId);
      return;
    }
    _hiddenPlaylistIds.add(playlistId);
    _pinnedItemIds.remove('playlist:$playlistId');
    _playlists = _playlists.where((p) => p.id != playlistId).toList();
    _notifyListeners();
    await _savePreferences();
  }

  Future<void> _deleteCreatedPlaylist(String playlistId) async {
    final client = _client;
    _playlistEdits.remove(playlistId);
    _pinnedItemIds.remove('playlist:$playlistId');
    _reapplyPlaylistEdits();
    _sortLibrary();
    _notifyListeners();
    if (client == null) return;
    try {
      await client.deletePlaylistEdit(playlistId);
    } catch (_) {
      // Best-effort: the local removal already reflects the user's intent. If
      // the server call failed the edit will simply reappear on the next sync.
    }
  }

  Future<void> _togglePin(String key) async {
    final client = _client;
    if (client == null) return;
    final separator = key.indexOf(':');
    if (separator <= 0 || separator >= key.length - 1) return;
    final type = key.substring(0, separator);
    final targetId = key.substring(separator + 1);
    if (_pinnedItemIds.contains(key)) {
      await client.unpin(type, targetId);
    } else {
      await client.pin(type, targetId);
    }
    await refreshPins();
  }

  void _applyPins(List<PinnedMediaItem> pins) {
    _pins = List<PinnedMediaItem>.from(pins)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _pinnedItemIds
      ..clear()
      ..addAll(_pins.map((pin) => pin.key));
  }

  Future<void> _migrateLegacyPlaylistOverrides(PlayerApiClient client) async {
    if (_pendingLegacyPlaylistNames.isEmpty &&
        _pendingLegacyPlaylistSongs.isEmpty) {
      return;
    }

    final ids = <String>{
      ..._pendingLegacyPlaylistNames.keys,
      ..._pendingLegacyPlaylistSongs.keys,
    };
    for (final playlistId in ids) {
      final base = _basePlaylistById(playlistId);
      if (base == null) continue;
      final songIds = _pendingLegacyPlaylistSongs[playlistId] ??
          _playlistById(playlistId)?.songIds ??
          base.songIds;
      final edit = PlaylistEdit(
        playlistId: playlistId,
        name: _pendingLegacyPlaylistNames[playlistId],
        songIds: List<String>.from(songIds),
        baseSnapshot: List<String>.from(base.songIds),
      );
      await client.putPlaylistEdit(
        playlistId,
        songIds: edit.songIds,
        name: edit.name,
        baseSnapshot: edit.baseSnapshot,
      );
      if (!identical(client, _client)) return;
      _playlistEdits[playlistId] = edit;
    }

    _pendingLegacyPlaylistNames.clear();
    _pendingLegacyPlaylistSongs.clear();
    _reapplyPlaylistEdits();
    await _savePreferences();
  }

  Future<void> _updatePlaylistSongs(
    String playlistId,
    List<String> Function(List<String>) update,
  ) async {
    final current = _playlistSongIds(playlistId);
    if (current == null) return;
    final songIds = update(List<String>.from(current));
    await _putPlaylistEditOptimistically(
      playlistId,
      songIds: songIds,
      name: _playlistEdits[playlistId]?.name,
    );
  }

  // An emptied Liked Songs drops out of [_playlists] but keeps its edit, so
  // it can still be refilled (e.g. from the playlists menu).
  List<String>? _playlistSongIds(String playlistId) =>
      _playlistById(playlistId)?.songIds ?? _playlistEdits[playlistId]?.songIds;

  PlaylistSummary? _playlistById(String playlistId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    return index >= 0 ? _playlists[index] : null;
  }

  PlaylistSummary? _basePlaylistById(String playlistId) {
    final index = _basePlaylists.indexWhere((p) => p.id == playlistId);
    return index >= 0 ? _basePlaylists[index] : null;
  }

  Future<void> _putPlaylistEditOptimistically(
    String playlistId, {
    required List<String> songIds,
    required String? name,
  }) async {
    final client = _client;
    final base = _basePlaylistById(playlistId);
    // Client-created playlists have no server base; their edit is authoritative
    // and carries an empty base snapshot.
    final accountOwned = isAccountOwnedPlaylistId(playlistId);
    final offlineCapable = playlistId == likedSongsPlaylistId;
    if ((client == null && (!offlineCapable || _activeSnapshotScope == null)) ||
        (base == null && !accountOwned)) {
      return;
    }

    final previousEdits = Map<String, PlaylistEdit>.from(_playlistEdits);
    final previousPlaylists = List<PlaylistSummary>.from(_playlists);
    final baseSnapshot =
        base != null ? List<String>.from(base.songIds) : <String>[];
    final edit = PlaylistEdit(
      playlistId: playlistId,
      name: name,
      songIds: List<String>.from(songIds),
      baseSnapshot: baseSnapshot,
    );

    _playlistEdits[playlistId] = edit;
    _reapplyPlaylistEdits();
    _sortLibrary();
    _error = null;
    _notifyListeners();

    if (playlistId == likedSongsPlaylistId) {
      _pendingPlaylistEdits[playlistId] = edit;
      await _saveSnapshot();
      if (client == null) return;
      await _replayPendingPlaylistEdits(client);
      return;
    }

    if (client == null) return;
    try {
      await client.putPlaylistEdit(
        playlistId,
        songIds: edit.songIds,
        name: edit.name,
        baseSnapshot: edit.baseSnapshot,
      );
    } on PlayerApiException catch (e) {
      if (!identical(client, _client)) return;
      _playlistEdits
        ..clear()
        ..addAll(previousEdits);
      _playlists = previousPlaylists;
      _error = e.message;
      _notifyListeners();
    } catch (e) {
      if (!identical(client, _client)) return;
      _playlistEdits
        ..clear()
        ..addAll(previousEdits);
      _playlists = previousPlaylists;
      _error = '$e';
      _notifyListeners();
    }
  }

  void _applyPlaylistEdits(List<PlaylistEdit> edits) {
    _playlistEdits
      ..clear()
      ..addEntries(edits.map((edit) => MapEntry(edit.playlistId, edit)))
      // A queued local edit is newer user intent than the fetched server row.
      ..addAll(_pendingPlaylistEdits);
    _reapplyPlaylistEdits();
  }

  Future<void> _replayPendingPlaylistEdits(PlayerApiClient client) async {
    if (_pendingPlaylistEdits.isEmpty || _isSyncingPendingPlaylistEdits) {
      return;
    }
    _isSyncingPendingPlaylistEdits = true;
    var requestFailed = false;
    try {
      while (_pendingPlaylistEdits.isNotEmpty) {
        final entry = _pendingPlaylistEdits.entries.first;
        final edit = entry.value;
        await client.putPlaylistEdit(
          edit.playlistId,
          songIds: edit.songIds,
          name: edit.name,
          baseSnapshot: edit.baseSnapshot,
        );
        if (!identical(client, _client)) return;
        // A newer toggle may have replaced this row while the request was in
        // flight. Only remove the exact edit that reached the server; the loop
        // then sends the newer state last.
        if (identical(_pendingPlaylistEdits[entry.key], edit)) {
          _pendingPlaylistEdits.remove(entry.key);
        }
        _error = null;
      }
    } on PlayerApiException catch (e) {
      requestFailed = true;
      if (identical(client, _client)) _error = e.message;
    } catch (e) {
      requestFailed = true;
      if (identical(client, _client)) _error = '$e';
    } finally {
      _isSyncingPendingPlaylistEdits = false;
      await _saveSnapshot();
      _notifyListeners();
      // Close the tiny race where a toggle lands after the loop sees an empty
      // queue but before the in-flight flag is cleared.
      if (!requestFailed &&
          _pendingPlaylistEdits.isNotEmpty &&
          identical(client, _client)) {
        unawaited(_replayPendingPlaylistEdits(client));
      }
    }
  }

  void _reapplyPlaylistEdits() {
    final base = _basePlaylists
        .where((playlist) => !_hiddenPlaylistIds.contains(playlist.id))
        .map(_applyPlaylistEdit);
    final created = _playlistEdits.keys
        .where(isAccountOwnedPlaylistId)
        .where(
          (id) =>
              id != likedSongsPlaylistId ||
              _playlistEdits[id]!.songIds.isNotEmpty,
        )
        .where((id) => !_hiddenPlaylistIds.contains(id))
        .map(_buildAccountOwnedPlaylist)
        .whereType<PlaylistSummary>();
    _playlists = <PlaylistSummary>[...base, ...created];
  }

  /// Builds an account-owned [PlaylistSummary] directly from its edit (there
  /// is no server base to reconcile against).
  PlaylistSummary? _buildAccountOwnedPlaylist(String playlistId) {
    final edit = _playlistEdits[playlistId];
    if (edit == null) return null;
    final live = _songs.map((song) => song.id).toSet();
    final effective = edit.songIds.where(live.contains).toList();
    final name = edit.name?.trim();
    return _withSongStats(PlaylistSummary(
      id: playlistId,
      name: playlistId == likedSongsPlaylistId
          ? 'Liked Songs'
          : (name != null && name.isNotEmpty)
              ? name
              : 'Playlist',
      songIds: effective,
    ));
  }

  bool _isCreatedPlaylistId(String playlistId) =>
      isCreatedPlaylistId(playlistId);

  String _newCreatedPlaylistId() => newCreatedPlaylistId();

  PlaylistSummary _applyPlaylistEdit(PlaylistSummary playlist) {
    final live = _songs.map((song) => song.id).toSet();
    final edit = _playlistEdits[playlist.id];
    if (edit == null) {
      return _withSongStats(playlist.copyWith(
        songIds: playlist.songIds.where(live.contains).toList(),
      ));
    }

    final effective = edit.songIds.where(live.contains).toList();
    final effectiveSet = effective.toSet();
    final baseSnapshot = edit.baseSnapshot.toSet();
    for (final id in playlist.songIds) {
      if (!live.contains(id) ||
          baseSnapshot.contains(id) ||
          effectiveSet.contains(id)) {
        continue;
      }
      effective.add(id);
      effectiveSet.add(id);
    }

    return _withSongStats(playlist.copyWith(
      name: edit.name,
      songIds: effective,
    ));
  }

  PlaylistSummary _withSongStats(PlaylistSummary playlist) {
    final songsById = <String, Track>{for (final song in _songs) song.id: song};
    final duration = playlist.songIds.fold<int>(
      0,
      (total, id) => total + (songsById[id]?.durationSeconds ?? 0),
    );
    return playlist.copyWith(
      songCount: playlist.songIds.length,
      durationSeconds: duration,
    );
  }

  void _sortLibrary() {
    _albums.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    _playlists.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }
}
