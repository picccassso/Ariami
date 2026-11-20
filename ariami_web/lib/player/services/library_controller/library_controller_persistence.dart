part of '../library_controller.dart';

extension _LibraryControllerPersistence on LibraryController {
  String? get _preferencesKey {
    final accountKey = _accountKey;
    if (accountKey == null) return null;
    final scope = base64Url.encode(utf8.encode(accountKey)).replaceAll('=', '');
    return '${LibraryController._preferencesPrefix}$scope';
  }

  Future<void> _loadPreferences(PlayerApiClient client) async {
    final key = _preferencesKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!identical(client, _client)) return;
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _pendingLegacyPlaylistNames.addAll(
        (json['playlistNames'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value as String)),
      );
      final songs = json['playlistSongs'] as Map<String, dynamic>? ?? const {};
      for (final entry in songs.entries) {
        _pendingLegacyPlaylistSongs[entry.key] =
            (entry.value as List<dynamic>).cast<String>();
      }
      _hiddenPlaylistIds.addAll(
        (json['hiddenPlaylists'] as List<dynamic>? ?? const []).cast<String>(),
      );
      _recentSearches = (json['recentSearches'] as List<dynamic>? ?? const [])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .take(_searchSettings.recentSearchesLimit)
          .toList();
    } catch (_) {
      // Ignore corrupt local preferences and keep the server library usable.
    }
  }

  Future<void> _savePreferences() async {
    final key = _preferencesKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(<String, dynamic>{
        'hiddenPlaylists': _hiddenPlaylistIds.toList(),
        'recentSearches': _recentSearches.map((t) => t.toJson()).toList(),
      }),
    );
  }

  /// Writes the effective library (songs, albums, playlists with edits
  /// applied) to the configured snapshot store so [loadOfflineSnapshot] can
  /// restore it without a server.
  Future<void> _saveSnapshot() async {
    final store = _snapshotStore;
    final scope = _activeSnapshotScope ?? _preferencesKey;
    if (store == null || scope == null) return;
    try {
      await store.write(
        scope,
        jsonEncode(<String, dynamic>{
          'version': desktopLibrarySnapshotVersion,
          'songs': _songs.map((t) => t.toJson()).toList(),
          'albums': _albums.map((a) => a.toJson()).toList(),
          'playlists': _playlists.map((pl) => pl.toJson()).toList(),
          'curation': _curation.toJson(),
          'playlistEdits': _playlistEdits.values.map((e) => e.toJson()).toList(),
          'pendingPlaylistEdits':
              _pendingPlaylistEdits.values.map((e) => e.toJson()).toList(),
          'playlistImageVersions': _playlistImageVersions,
          'artistImageVersions': _artistImageVersions,
          'syncToken': _syncToken,
        }),
      );
      await store.writeLastScope(scope);
    } catch (_) {}
  }

  /// Restores the last-connected account's library from the snapshot store,
  /// for offline mode. No client is attached; server-backed actions stay
  /// no-ops. Returns whether a snapshot was loaded.
  Future<bool> _loadOfflineSnapshot() async {
    final store = _snapshotStore;
    if (_client != null || store == null) return false;
    try {
      final scope = await store.readLastScope();
      if (scope == null || scope.isEmpty) return false;
      return _loadSnapshot(scope, offline: true);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _loadSnapshot(
    String? scope, {
    PlayerApiClient? expectedClient,
    required bool offline,
  }) async {
    if (_snapshotStore == null || scope == null || scope.isEmpty) return false;
    // A stale or corrupt snapshot must never throw into load(): its catch
    // treats the error as fatal and skips the network fetch, and the snapshot
    // is only rewritten after a successful fetch — so it would never self-heal.
    try {
      return await _loadSnapshotUnsafe(
        scope,
        expectedClient: expectedClient,
        offline: offline,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _loadSnapshotUnsafe(
    String scope, {
    PlayerApiClient? expectedClient,
    required bool offline,
  }) async {
    final store = _snapshotStore;
    if (store == null) return false;
    final raw = await store.read(scope);
    if (raw == null || raw.isEmpty) return false;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (expectedClient != null && !identical(expectedClient, _client)) {
      return false;
    }
    if (offline && _client != null) return false;
    final snapshotSongs = (json['songs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    _albums = (json['albums'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Album.fromJson)
        .toList();
    _songs = hydrateTrackAlbumMetadata(snapshotSongs, _albums);
    final rawCuration = json['curation'];
    if (rawCuration is Map<String, dynamic>) {
      _applyCuration(UserLibraryCuration.fromJson(rawCuration));
    }
    final snapshotPlaylists =
        (json['playlists'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(PlaylistSummary.fromJson)
            .toList();
    _activeSnapshotScope = scope;
    _basePlaylists = snapshotPlaylists
        .where((playlist) => !isAccountOwnedPlaylistId(playlist.id))
        .toList();
    _playlistEdits
      ..clear()
      ..addEntries(
        (json['playlistEdits'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(PlaylistEdit.fromJson)
            .map((edit) => MapEntry(edit.playlistId, edit)),
      );
    // Backward compatibility for snapshots written before edits were stored.
    for (final playlist in snapshotPlaylists.where(
      (playlist) => isAccountOwnedPlaylistId(playlist.id),
    )) {
      _playlistEdits.putIfAbsent(
        playlist.id,
        () => PlaylistEdit(
          playlistId: playlist.id,
          name: playlist.name,
          songIds: List<String>.from(playlist.songIds),
          baseSnapshot: const <String>[],
        ),
      );
    }
    _pendingPlaylistEdits
      ..clear()
      ..addEntries(
        (json['pendingPlaylistEdits'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(PlaylistEdit.fromJson)
            .map((edit) => MapEntry(edit.playlistId, edit)),
      );
    _playlistEdits.addAll(_pendingPlaylistEdits);
    _reapplyPlaylistEdits();
    final playlistImages = (json['playlistImageVersions']
                as Map<String, dynamic>? ??
            const <String, dynamic>{})
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    _playlistImageVersions
      ..clear()
      ..addAll(playlistImages);
    final artistImages = (json['artistImageVersions']
                as Map<String, dynamic>? ??
            const <String, dynamic>{})
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    _artistImageVersions
      ..clear()
      ..addAll(artistImages);
    _albumDetailCache.clear();
    // A snapshot from another schema version may have advanced its token past
    // changes it could not decode, so its cached songs can be missing newer
    // fields. Keep showing it, but start from zero so the next load refetches.
    final schemaMatches =
        (json['version'] as num?)?.toInt() == desktopLibrarySnapshotVersion;
    _syncToken = schemaMatches ? (json['syncToken'] as num?)?.toInt() ?? 0 : 0;
    _sortLibrary();
    _isOfflineSnapshot = offline;
    _error = null;
    _notifyListeners();
    return hasContent;
  }
}
