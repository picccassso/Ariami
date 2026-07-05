part of 'library_controller.dart';

extension _LibraryControllerPreferences on LibraryController {
  Future<void> _loadUiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _updateState(_state.copyWith(
      isGridView: prefs.getBool(LibraryController._viewPreferenceKey) ?? true,
      albumsExpanded:
          prefs.getBool(LibraryController._albumsSectionKey) ?? true,
      songsExpanded: prefs.getBool(LibraryController._songsSectionKey) ?? false,
      isMixedMode: prefs.getBool(LibraryController._mixedModeKey) ?? false,
    ));
  }

  Future<void> _toggleViewMode() async {
    final newValue = !_state.isGridView;
    _updateState(_state.copyWith(isGridView: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LibraryController._viewPreferenceKey, newValue);
  }

  Future<void> _toggleAlbumsExpanded() async {
    final newValue = !_state.albumsExpanded;
    _updateState(_state.copyWith(albumsExpanded: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LibraryController._albumsSectionKey, newValue);
  }

  Future<void> _toggleSongsExpanded() async {
    final newValue = !_state.songsExpanded;
    _updateState(_state.copyWith(songsExpanded: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LibraryController._songsSectionKey, newValue);
  }

  Future<void> _toggleMixedMode() async {
    final newValue = !_state.isMixedMode;
    _updateState(_state.copyWith(isMixedMode: newValue));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LibraryController._mixedModeKey, newValue);
  }

  void _toggleShowDownloadedOnly() {
    _updateState(
      _state.copyWith(showDownloadedOnly: !_state.showDownloadedOnly),
    );
  }

  Future<void> _loadPlayedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(LibraryController._lastPlayedKey);
    if (jsonString == null || jsonString.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final playedHistory = <String, DateTime>{};

      decoded.forEach((key, value) {
        final epochMs = value is int ? value : int.tryParse(value.toString());
        if (epochMs != null) {
          playedHistory[key] = DateTime.fromMillisecondsSinceEpoch(epochMs);
        }
      });

      _updateState(_state.copyWith(itemLastPlayedAt: playedHistory));
    } catch (_) {
      // Ignore corrupt local played history and keep running.
    }
  }

  Future<void> _markItemPlayed(String key) async {
    final now = DateTime.now();
    final updatedPlayedHistory =
        Map<String, DateTime>.from(_state.itemLastPlayedAt)..[key] = now;

    _updateState(_state.copyWith(itemLastPlayedAt: updatedPlayedHistory));
    await _persistPlayedHistory(updatedPlayedHistory);
  }

  Future<void> _persistPlayedHistory(Map<String, DateTime> history) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = history.map(
      (entryKey, value) => MapEntry(entryKey, value.millisecondsSinceEpoch),
    );
    await prefs.setString(
        LibraryController._lastPlayedKey, jsonEncode(encoded));
  }

  /// Re-point album-keyed pins and recents from old album IDs to the current
  /// ones after a server-side album identity change (e.g. tag normalization
  /// re-hashing album IDs). [oldToNew] holds exact old -> new pairs discovered
  /// while remapping downloads; playlist keys are untouched.
  Future<void> _remapAlbumPreferenceKeys(Map<String, String> oldToNew) async {
    final result = remapAlbumKeys(
      pins: _state.pinnedItemIds,
      recents: _state.itemLastPlayedAt,
      oldToNew: oldToNew,
    );
    if (!result.hasChanges) return;

    _updateState(_state.copyWith(
      pinnedItemIds: result.pinsChanged ? result.pins : null,
      itemLastPlayedAt: result.recentsChanged ? result.recents : null,
    ));

    if (result.pinsChanged) await _savePinnedItems();
    if (result.recentsChanged) await _persistPlayedHistory(result.recents);
  }

  Future<void> _loadPinnedItems() async {
    Set<String> pinnedItemIds;
    final client = _connectionService.apiClient;
    if (client != null && _connectionService.isAuthenticated) {
      final pins = await client.getPins();
      pinnedItemIds = pins
          .where((pin) => pin['type'] is String && pin['targetId'] is String)
          .map((pin) => '${pin['type']}:${pin['targetId']}')
          .toSet();
      await LibraryPinStorage.saveForUser(
        _connectionService.userId,
        pinnedItemIds,
      );
    } else {
      pinnedItemIds =
          await LibraryPinStorage.loadForUser(_connectionService.userId);
    }
    // Imported server playlists have a local editable id. Mirror the
    // canonical server pin under that id for UI lookup only; the persisted
    // cache and all writes retain the stable server id.
    for (final entry in _playlistService.importedFromServer.entries) {
      if (pinnedItemIds.contains('playlist:${entry.value}')) {
        pinnedItemIds.add('playlist:${entry.key}');
      }
    }
    _updateState(_state.copyWith(pinnedItemIds: pinnedItemIds));
  }

  Future<void> _savePinnedItems() async {
    final canonical = <String>{};
    for (final key in _state.pinnedItemIds) {
      if (!key.startsWith('playlist:')) {
        canonical.add(key);
        continue;
      }
      final localId = key.substring('playlist:'.length);
      final stableId = _playlistService.getServerPlaylistId(localId) ?? localId;
      canonical.add('playlist:$stableId');
    }
    await LibraryPinStorage.saveForUser(
      _connectionService.userId,
      canonical,
    );
  }

  Future<void> _togglePinAlbum(String albumId) async {
    await _togglePin('album:$albumId');
  }

  Future<void> _togglePinPlaylist(String playlistId) async {
    final stableId =
        _playlistService.getServerPlaylistId(playlistId) ?? playlistId;
    await _togglePin('playlist:$stableId');
  }

  Future<void> _togglePin(String key) async {
    final separator = key.indexOf(':');
    if (separator <= 0 || separator >= key.length - 1) return;
    final client = _connectionService.apiClient;
    if (client != null && _connectionService.isAuthenticated) {
      final type = key.substring(0, separator);
      final targetId = key.substring(separator + 1);
      if (_state.pinnedItemIds.contains(key)) {
        await client.unpinItem(type, targetId);
      } else {
        await client.pinItem(type, targetId);
      }
      await _loadPinnedItems();
      return;
    }

    // Offline cache is only a convenience; the next successful server fetch
    // replaces it so stale local state can never beat the account truth.
    final updated = Set<String>.from(_state.pinnedItemIds);
    if (!updated.remove(key)) updated.add(key);
    _updateState(_state.copyWith(pinnedItemIds: updated));
    await _savePinnedItems();
  }

  void _onPlaylistsChanged() {
    _notifyListeners();
  }
}
