part of 'library_controller.dart';

extension _LibraryControllerLoading on LibraryController {
  Future<LibraryRefreshOutcome> _refreshLibrary() async {
    if (_offlineService.isManualOfflineModeEnabled) {
      final outcome = await reconnectFromManualOffline(
        offline: _offlineService,
        connection: _connectionService,
      );
      await _loadLibrary(background: true);
      switch (outcome) {
        case ManualOfflineReconnectOutcome.success:
          return LibraryRefreshOutcome.ok;
        case ManualOfflineReconnectOutcome.authFailure:
          return LibraryRefreshOutcome.showSessionExpiredSnack;
        case ManualOfflineReconnectOutcome.networkFailure:
          return LibraryRefreshOutcome.showManualReconnectFailedSnack;
      }
    }

    if (_offlineService.isOfflineModeEnabled ||
        !_connectionService.isConnected ||
        _connectionService.apiClient == null) {
      final restored = await _connectionService.tryRestoreConnection();
      if (!restored) {
        if (!_connectionService.hasServerInfo) {
          await _loadLibrary(background: true);
          return LibraryRefreshOutcome.navigateToReconnectScreen;
        }
        if (_connectionService.didLastRestoreFailForAuth) {
          await _loadLibrary(background: true);
          return LibraryRefreshOutcome.showSessionExpiredSnack;
        }
        await _loadLibrary(background: true);
        return LibraryRefreshOutcome.ok;
      }
    }

    if (!_offlineService.isOfflineModeEnabled &&
        _connectionService.isConnected &&
        _connectionService.apiClient != null) {
      try {
        await _connectionService.librarySyncEngine.rebuildFromServer();
      } catch (_) {
        // Sync errors are recorded in the engine; keep serving local data.
      }
    }

    await _loadLibrary(background: true);

    if (!_offlineService.isOfflineModeEnabled &&
        _connectionService.isConnected) {
      final syncHealth =
          await _connectionService.librarySyncEngine.getSyncHealth();
      if (syncHealth.hasSyncFailure) {
        return LibraryRefreshOutcome.showSyncFailedSnack;
      }
    }

    return LibraryRefreshOutcome.ok;
  }

  Future<void> _loadLibrary({bool background = false}) async {
    if (_isLibraryLoadInFlight) {
      _pendingBackgroundReload = true;
      return;
    }

    libraryLoadAttemptsForTest++;
    final hasExistingContent = _state.albums.isNotEmpty ||
        _state.songs.isNotEmpty ||
        _state.offlineSongs.isNotEmpty;
    final useFullScreenLoader = !background && !hasExistingContent;

    _isLibraryLoadInFlight = true;
    try {
      if (_offlineService.isOfflineModeEnabled) {
        _clearDurationRetries();
        await _loadDownloadedSongs();
        if (hasExistingContent) {
          _pendingScrollRestore = true;
        }
        _buildLibraryFromDownloads();
        await _loadDownloadedSongs();
        _updateState(_state.copyWith(
          isLoading: false,
          isRefreshing: false,
          clearError: true,
          clearSyncWarning: true,
          showDownloadedOnly: true,
        ));
        return;
      }

      if (_connectionService.apiClient == null) {
        // Not connected yet - most often the startup background reconnect is
        // still in flight. If a previous sync left a catalog on disk, render it
        // immediately from the local store (no network needed) so the user sees
        // their library right away; the reconnect refreshes it when it lands.
        // The local-store reads and download reconciliation in
        // _loadLibraryFromFacade never touch the apiClient.
        final hasLocalLibrary =
            await _connectionService.libraryReadFacade.hasCompletedBootstrap();
        if (hasLocalLibrary) {
          await _loadLibraryFromFacade();
          return;
        }

        _clearDurationRetries();
        _updateState(_state.copyWith(
          isLoading: false,
          isRefreshing: false,
          errorMessage: 'Not connected to server',
        ));
        return;
      }

      if (useFullScreenLoader) {
        _updateState(_state.copyWith(
          isLoading: true,
          isRefreshing: false,
          clearError: true,
        ));
      } else {
        _updateState(_state.copyWith(
          isRefreshing: true,
          isLoading: false,
          clearError: true,
        ));
      }

      await _loadLibraryFromFacade();
    } catch (e) {
      if (e.toString().contains('Network error') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('SocketException')) {
        _clearDurationRetries();
        if (background && hasExistingContent) {
          _updateState(_state.copyWith(
            isLoading: false,
            isRefreshing: false,
            syncWarningMessage: 'Library sync failed. Showing cached data.',
          ));
        } else {
          if (hasExistingContent) {
            _pendingScrollRestore = true;
          }
          await _loadDownloadedSongs();
          _buildLibraryFromDownloads();
          _updateState(_state.copyWith(
            isLoading: false,
            isRefreshing: false,
            clearError: true,
            clearSyncWarning: true,
            showDownloadedOnly: true,
          ));
        }
      } else {
        _clearDurationRetries();
        _updateState(_state.copyWith(
          isLoading: false,
          isRefreshing: false,
          errorMessage: 'Failed to load library: $e',
        ));
      }
    } finally {
      await _completeLibraryLoad();
    }
  }

  Future<void> _completeLibraryLoad() async {
    _isLibraryLoadInFlight = false;
    if (_pendingBackgroundReload) {
      _pendingBackgroundReload = false;
      unawaited(_loadLibrary(background: true));
      return;
    }
    await _recheckStaleSyncWarning();
  }

  Future<void> _recheckStaleSyncWarning() async {
    if (_state.syncWarningMessage == null) return;
    if (_offlineService.isOfflineModeEnabled) return;
    if (_connectionService.apiClient == null) return;

    try {
      final health = await _connectionService.librarySyncEngine.getSyncHealth();
      if (!health.isPartialRead && !health.hasSyncFailure) {
        _updateState(_state.copyWith(
          clearSyncWarning: true,
          isRefreshing: false,
        ));
      }
    } catch (_) {
      // Keep the existing warning if health cannot be queried.
    }
  }

  Future<void> _loadLibraryFromFacade() async {
    final library =
        await _connectionService.libraryReadFacade.getLibraryBundle();

    _playlistService.updateServerPlaylists(library.serverPlaylists);

    final validSongIds = library.songs.map((song) => song.id).toSet();
    final validAlbumIds = library.albums.map((album) => album.id).toSet();
    await _downloadManager.pruneOrphanedIncompleteDownloads(validSongIds);
    await _downloadManager.relinkOrphanedCompletedDownloads(
      librarySongs: library.songs,
      libraryAlbums: library.albums,
    );
    // Re-point downloads whose album ID changed (e.g. after a server-side tag
    // normalization re-hashed album identities) so they aren't mistaken for
    // orphaned offline copies. Reuse the discovered old -> new album ID pairs to
    // migrate album-keyed pins and recents to match.
    final albumIdRemap = await _downloadManager.migrateDownloadAlbumIds(
      librarySongs: library.songs,
      libraryAlbums: library.albums,
    );
    await _remapAlbumPreferenceKeys(albumIdRemap);
    await _downloadManager.refreshDownloadAlbumMetadata(
      libraryAlbums: [
        ..._state.albums.where(
          (album) => !_state.isOfflineCopyAlbum(album.id),
        ),
        ...library.albums,
      ],
    );
    await _offlineCopyService.reconcileAlbums(
      tasks: _downloadManager.queue,
      serverSongIds: validSongIds,
      serverAlbumIds: validAlbumIds,
    );
    final retainedAlbums = _buildRetainedOfflineAlbums();
    final retainedSongs = _buildRetainedOfflineSongs();
    _hasLoadedOnlineLibrary = true;

    _updateState(_state.copyWith(
      albums: [...library.albums, ...retainedAlbums],
      songs: library.songs,
      offlineCopySongs: retainedSongs,
      offlineCopyAlbumIds: _offlineCopyService.retainedAlbumIds,
      isOfflineMode: false,
      isLoading: false,
      isRefreshing: false,
      showDownloadedOnly: false,
      syncWarningMessage: _buildSyncWarningMessage(library),
      clearSyncWarning: !_hasSyncWarning(library),
    ));

    if (library.durationsReady) {
      _clearDurationRetries();
    } else {
      _durationsPending = true;
      _scheduleDurationRetry();
    }

    await _playlistService.remapPlaylistSongIds(library.songs);
    await _statsService.remapStaleStatIdsFromLibrary(library.songs);
    await _playlistService.rehydrateSongMetadataFromLibrary(library.songs);
    await _loadDownloadedSongs();
  }

  bool _hasSyncWarning(LibraryReadBundle library) {
    return library.isPartialRead || library.syncHealth?.hasSyncFailure == true;
  }

  String? _buildSyncWarningMessage(LibraryReadBundle library) {
    if (library.syncHealth?.hasSyncFailure == true) {
      return 'Library sync failed. Showing cached data.';
    }
    if (library.isPartialRead) {
      return 'Library sync is still in progress. Some content may be missing.';
    }
    return null;
  }
}
