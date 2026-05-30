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

    final prefs = await SharedPreferences.getInstance();
    final encoded = updatedPlayedHistory.map(
      (entryKey, value) => MapEntry(entryKey, value.millisecondsSinceEpoch),
    );
    await prefs.setString(
        LibraryController._lastPlayedKey, jsonEncode(encoded));
  }

  Future<void> _loadPinnedItems() async {
    final pinnedItemIds =
        await LibraryPinStorage.loadForUser(_connectionService.userId);
    _updateState(_state.copyWith(pinnedItemIds: pinnedItemIds));
  }

  Future<void> _savePinnedItems() async {
    await LibraryPinStorage.saveForUser(
      _connectionService.userId,
      _state.pinnedItemIds,
    );
  }

  Future<void> _togglePinAlbum(String albumId) async {
    await _togglePin('album:$albumId');
  }

  Future<void> _togglePinPlaylist(String playlistId) async {
    await _togglePin('playlist:$playlistId');
  }

  Future<void> _togglePin(String key) async {
    final updated = Set<String>.from(_state.pinnedItemIds);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    _updateState(_state.copyWith(pinnedItemIds: updated));
    await _savePinnedItems();
  }

  void _onPlaylistsChanged() {
    _notifyListeners();
  }
}
