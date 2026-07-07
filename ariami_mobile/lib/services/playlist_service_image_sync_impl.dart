part of 'playlist_service.dart';

/// Syncs custom playlist cover photos through the server's account-scoped
/// image store.
///
/// Photos are keyed server-side by the same ids as playlist edits: the server
/// playlist id for imported copies and the `created:` id for standalone
/// playlists. Outbound pushes queue for replay when the server is
/// unreachable, mirroring the pending-edit-push behaviour; while a push is
/// queued, inbound sync leaves that playlist's photo untouched so the local
/// intent wins.
extension _PlaylistServiceImageSyncImpl on PlaylistService {
  /// The server-side image key for a local playlist, or null when the
  /// playlist has no synced counterpart (a purely local playlist).
  String? _imageSyncIdForLocal(String localPlaylistId) {
    if (isCreatedPlaylistId(localPlaylistId)) return localPlaylistId;
    return _importedFromServer[localPlaylistId];
  }

  Future<Directory> _playlistImagesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/playlist_images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Pushes the local photo state (set or removed) of [localPlaylistId] to
  /// the server so the user's other devices pick it up. Queues for replay
  /// when the push cannot reach the server.
  Future<void> _pushPlaylistImageImpl(String localPlaylistId) async {
    final playlist = _getPlaylistImpl(localPlaylistId);
    final syncId = _imageSyncIdForLocal(localPlaylistId);
    if (playlist == null || syncId == null) return;

    final removing = playlist.customImagePath == null;
    _pendingPlaylistImagePushes[localPlaylistId] = removing ? 'delete' : 'put';
    await _savePendingPlaylistImagePushes();

    final connection = ConnectionService();
    final client = connection.apiClient;
    if (client == null || !connection.isAuthenticated) return;

    try {
      if (removing) {
        await client.deletePlaylistImage(syncId);
        _syncedPlaylistImageVersions.remove(syncId);
      } else {
        final file = File(playlist.customImagePath!);
        if (!await file.exists()) {
          await _clearPlaylistImagePushPending(localPlaylistId);
          return;
        }
        final bytes = await file.readAsBytes();
        final contentType = _sniffPlaylistImageContentType(bytes);
        if (contentType == null) {
          // A format the other clients cannot rely on decoding — keep the
          // photo local-only rather than retrying a doomed push forever.
          debugPrint(
            '[PlaylistService] Unsupported playlist photo format; not syncing',
          );
          await _clearPlaylistImagePushPending(localPlaylistId);
          return;
        }
        final updatedAt = await client.putPlaylistImage(
          syncId,
          bytes: bytes,
          contentType: contentType,
        );
        if (updatedAt != null) {
          _syncedPlaylistImageVersions[syncId] = updatedAt;
        }
      }
      await _saveSyncedPlaylistImageVersions();
      await _clearPlaylistImagePushPending(localPlaylistId);
    } catch (error) {
      debugPrint(
        '[PlaylistService] Queued playlist photo push after failure: $error',
      );
    }
  }

  /// Replays queued offline photo changes. Last writer wins, matching the
  /// pending edit-push replay.
  Future<void> _replayPendingPlaylistImagePushesImpl() async {
    if (_pendingPlaylistImagePushes.isEmpty ||
        _isReplayingPendingImagePushes) {
      return;
    }
    final connection = ConnectionService();
    if (connection.apiClient == null || !connection.isAuthenticated) return;

    _isReplayingPendingImagePushes = true;
    try {
      for (final localId in _pendingPlaylistImagePushes.keys.toList()) {
        if (_getPlaylistImpl(localId) == null ||
            _imageSyncIdForLocal(localId) == null) {
          // The playlist was deleted or unlinked while the push was queued.
          await _clearPlaylistImagePushPending(localId);
          continue;
        }
        await _pushPlaylistImageImpl(localId);
      }
    } finally {
      _isReplayingPendingImagePushes = false;
    }
  }

  /// Mirrors the server's image manifest onto the local playlist copies:
  /// downloads new/changed photos for imported and created playlists and
  /// clears photos that were removed on another device.
  Future<void> _applyServerPlaylistImagesImpl() async {
    final connection = ConnectionService();
    final client = connection.apiClient;
    if (client == null || !connection.isAuthenticated) return;

    final imagesBySyncId = <String, ServerPlaylistImage>{
      for (final image in _serverPlaylistImages) image.playlistId: image,
    };
    final localIdBySyncId = <String, String>{
      for (final entry in _importedFromServer.entries) entry.value: entry.key,
      for (final playlist in _playlists)
        if (isCreatedPlaylistId(playlist.id)) playlist.id: playlist.id,
    };

    var playlistsChanged = false;
    var versionsChanged = false;
    for (final entry in localIdBySyncId.entries) {
      final syncId = entry.key;
      final localId = entry.value;
      // A queued local photo change is this device's newest intent; don't
      // clobber it with the server state it is about to replace.
      if (_pendingPlaylistImagePushes.containsKey(localId)) continue;

      final remote = imagesBySyncId[syncId];
      final syncedVersion = _syncedPlaylistImageVersions[syncId];

      if (remote == null) {
        // No server image. If one was synced down before, it was removed on
        // another device; drop the local copy. A photo that never synced
        // (no recorded version) stays untouched.
        if (syncedVersion == null) continue;
        _syncedPlaylistImageVersions.remove(syncId);
        versionsChanged = true;
        final index =
            _playlists.indexWhere((playlist) => playlist.id == localId);
        if (index != -1 && _playlists[index].customImagePath != null) {
          _deletePlaylistImageFile(_playlists[index].customImagePath);
          _playlists[index] = _playlists[index].copyWith(
            clearCustomImagePath: true,
            modifiedAt: DateTime.now(),
          );
          playlistsChanged = true;
        }
        continue;
      }

      var index = _playlists.indexWhere((playlist) => playlist.id == localId);
      if (index == -1) continue;
      final currentPath = _playlists[index].customImagePath;
      final upToDate = syncedVersion == remote.updatedAt &&
          currentPath != null &&
          File(currentPath).existsSync();
      if (upToDate) continue;

      try {
        final bytes = await client.getPlaylistImage(syncId);
        if (bytes == null || bytes.isEmpty) continue;
        final path =
            await _writeSyncedPlaylistImageFile(localId, remote, bytes);
        // Recompute: the list may have shifted across the awaits above.
        index = _playlists.indexWhere((playlist) => playlist.id == localId);
        if (index == -1) continue;
        final previousPath = _playlists[index].customImagePath;
        if (previousPath != null && previousPath != path) {
          _deletePlaylistImageFile(previousPath);
        }
        _playlists[index] = _playlists[index].copyWith(
          customImagePath: path,
          modifiedAt: DateTime.now(),
        );
        _syncedPlaylistImageVersions[syncId] = remote.updatedAt;
        versionsChanged = true;
        playlistsChanged = true;
      } catch (error) {
        // Transient failure: the next edits load retries the download.
        debugPrint('[PlaylistService] Failed to sync playlist photo: $error');
      }
    }

    if (versionsChanged) await _saveSyncedPlaylistImageVersions();
    if (playlistsChanged) {
      await _savePlaylists();
      _notifyListeners();
    }
  }

  /// Forgets image-sync tracking for a locally deleted playlist. The server
  /// copy is left alone: for imported playlists the image still belongs to
  /// the (restorable) server playlist, and for created playlists the server
  /// deletes it together with the edit.
  Future<void> _forgetPlaylistImageSync(
    String localPlaylistId,
    String? syncId,
  ) async {
    if (_pendingPlaylistImagePushes.remove(localPlaylistId) != null) {
      await _savePendingPlaylistImagePushes();
    }
    if (syncId != null &&
        _syncedPlaylistImageVersions.remove(syncId) != null) {
      await _saveSyncedPlaylistImageVersions();
    }
  }

  Future<void> _clearPlaylistImagePushPending(String localPlaylistId) async {
    if (_pendingPlaylistImagePushes.remove(localPlaylistId) != null) {
      await _savePendingPlaylistImagePushes();
    }
  }

  Future<String> _writeSyncedPlaylistImageFile(
    String localPlaylistId,
    ServerPlaylistImage image,
    Uint8List bytes,
  ) async {
    final dir = await _playlistImagesDirectory();
    final safeId =
        localPlaylistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final extension = switch (image.contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final file = File(
      '${dir.path}/synced_${safeId}_${image.updatedAt}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Deletes a no-longer-referenced photo file. Only touches files inside
  /// the app's own playlist-images directory.
  void _deletePlaylistImageFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.path.contains('playlist_images') && file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup; a stale file is harmless.
    }
  }

  /// Maps image bytes to the content types the server accepts, or null for
  /// formats that should stay local-only (e.g. HEIC).
  String? _sniffPlaylistImageContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
