part of 'library_controller.dart';

extension _LibraryControllerLoading on LibraryController {
  Future<LibraryRefreshOutcome> _refreshLibrary() async {
    if (_offlineService.isManualOfflineModeEnabled) {
      final outcome = await reconnectFromManualOffline(
        offline: _offlineService,
        connection: _connectionService,
      );
      await Future.wait<void>([
        _loadLibrary(background: true),
        _loadServerPlaylistEditsIfConnected(),
      ]);
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
          return LibraryRefreshOutcome.navigateToWelcomeScreen;
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
        await _connectionService.librarySyncEngine.syncNow();
      } catch (_) {
        // Sync errors are recorded in the engine; keep serving local data.
      }
    }

    await Future.wait<void>([
      _loadLibrary(background: true),
      _loadServerPlaylistEditsIfConnected(),
    ]);

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

    await _applyLibraryBundle(library);
  }

  Future<void> _applyLibraryBundle(LibraryReadBundle library) async {
    final hasExistingCatalogue =
        _state.albums.isNotEmpty || _state.songs.isNotEmpty;

    // A bootstrap snapshot can contain only the pages synced so far. Keep a
    // previously complete catalogue visible until its complete replacement is
    // ready; otherwise the library appears to be randomly deleted.
    if (library.isPartialRead &&
        _hasLoadedOnlineLibrary &&
        hasExistingCatalogue) {
      _updateState(_state.copyWith(
        isLoading: false,
        isRefreshing: false,
        syncWarningMessage: _buildSyncWarningMessage(library),
      ));
      return;
    }

    final isAuthoritativeLibrary = !library.isPartialRead;
    if (!LibraryCurationService().isLoaded &&
        _connectionService.apiClient != null) {
      await LibraryCurationService().loadFromServer();
    }

    _rawOnlineAlbums = library.albums;
    _rawOnlineSongs = library.songs;
    _rawOnlineServerPlaylists = library.serverPlaylists;
    _rawOnlineGenreIndex = library.genreIndex;
    _rawDurationsReady = library.durationsReady;
    _rawSyncWarningMessage = _buildSyncWarningMessage(library);

    final filter = LibraryCurationService().filter;
    final filteredServerPlaylists = filter.filterPlaylists(
      library.serverPlaylists,
      idOf: (p) => p.id,
    );

    final validSongIds = library.songs.map((song) => song.id).toSet();
    final validAlbumIds = library.albums.map((album) => album.id).toSet();
    if (isAuthoritativeLibrary) {
      _playlistService.updateServerPlaylists(filteredServerPlaylists);
      await _downloadManager.pruneOrphanedIncompleteDownloads(
        validSongIds,
        isAuthoritativeLibrary: true,
      );
      await _downloadManager.relinkOrphanedCompletedDownloads(
        librarySongs: library.songs,
        libraryAlbums: library.albums,
      );
      // Re-point downloads whose album ID changed (e.g. after a server-side
      // tag normalization re-hashed album identities) so they aren't mistaken
      // for orphaned offline copies. Reuse the discovered old -> new album ID
      // pairs to migrate album-keyed pins and recents to match.
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
        librarySongs: library.songs,
      );
      await _offlineCopyService.reconcileAlbums(
        tasks: _downloadManager.queue,
        serverSongIds: validSongIds,
        serverAlbumIds: validAlbumIds,
      );
    }
    if (isAuthoritativeLibrary) {
      _hasLoadedOnlineLibrary = true;
    }

    _applyFilteredOnlineState(isLoadingComplete: true);

    if (library.durationsReady) {
      _clearDurationRetries();
    } else {
      _durationsPending = true;
      _scheduleDurationRetry();
    }

    if (isAuthoritativeLibrary) {
      await _playlistService.remapPlaylistSongIds(library.songs);
      await _statsService.remapStaleStatIdsFromLibrary(library.songs);
      await AlbumMetadataRepairMigration().run(library: library);
      await _playlistService.rehydrateSongMetadataFromLibrary(library.songs);
    }
    await _loadDownloadedSongs();
  }

  void _applyFilteredOnlineState({bool isLoadingComplete = false}) {
    final filter = LibraryCurationService().filter;
    final albumArtistById = <String, String>{
      for (final album in _rawOnlineAlbums) album.id: album.artist,
    };
    final visibleOnlineAlbums = filter.filterAlbums(
      _rawOnlineAlbums,
      idOf: (a) => a.id,
      artistOf: (a) => a.artist,
    );
    final visibleOnlineSongs = filter.filterSongs(
      _rawOnlineSongs,
      idOf: (s) => s.id,
      artistOf: (s) => s.artist,
      albumIdOf: (s) => s.albumId,
      albumArtistOf: (s) =>
          s.albumId != null ? albumArtistById[s.albumId!] : null,
    );
    final filteredServerPlaylists = filter.filterPlaylists(
      _rawOnlineServerPlaylists,
      idOf: (p) => p.id,
    );
    _playlistService.updateServerPlaylists(filteredServerPlaylists);

    final retainedAlbums = _buildRetainedOfflineAlbums();
    final retainedSongs = _buildRetainedOfflineSongs();
    final retainedGenreIndex = _buildDownloadGenreIndex(
      _downloadManager.queue.where(
        (task) =>
            task.status == DownloadStatus.completed &&
            task.albumId != null &&
            _offlineCopyService.isRetainedAlbum(task.albumId!),
      ),
    );
    final filteredOnlineGenres = _filterGenreIndex(
      _rawOnlineGenreIndex,
      {for (final a in visibleOnlineAlbums) a.id},
    );
    final genreIndex = LibraryGenreIndex.merge(
      <LibraryGenreIndex>[filteredOnlineGenres, retainedGenreIndex],
    );
    final selectedGenre = _state.genreFilter;
    final keepGenreFilter = selectedGenre != null &&
        genreIndex.genreAlbums.containsKey(selectedGenre);

    _updateState(_state.copyWith(
      albums: [...visibleOnlineAlbums, ...retainedAlbums],
      songs: visibleOnlineSongs,
      offlineCopySongs: retainedSongs,
      genreIndex: genreIndex,
      genreFilter: keepGenreFilter ? selectedGenre : null,
      clearGenreFilter: !keepGenreFilter,
      offlineCopyAlbumIds: _offlineCopyService.retainedAlbumIds,
      isOfflineMode: false,
      isLoading: isLoadingComplete ? false : _state.isLoading,
      isRefreshing: isLoadingComplete ? false : _state.isRefreshing,
      showDownloadedOnly: false,
      syncWarningMessage: _rawSyncWarningMessage,
      clearSyncWarning: _rawSyncWarningMessage == null && _rawDurationsReady,
    ));
  }

  LibraryGenreIndex _filterGenreIndex(
    LibraryGenreIndex raw,
    Set<String> visibleAlbumIds,
  ) {
    if (raw.genres.isEmpty ||
        visibleAlbumIds.length == _rawOnlineAlbums.length) {
      return raw;
    }
    final albumGenres = <String, List<String>>{};
    for (final id in visibleAlbumIds) {
      final genres = raw.albumGenres[id];
      if (genres != null && genres.isNotEmpty) {
        albumGenres[id] = genres;
      }
    }
    final genreAlbums = <String, Set<String>>{};
    for (final entry in raw.genreAlbums.entries) {
      final subset = entry.value.where(visibleAlbumIds.contains).toSet();
      if (subset.isNotEmpty) {
        genreAlbums[entry.key] = subset;
      }
    }
    final genres = genreAlbums.keys.toList()
      ..sort((a, b) {
        final countCmp =
            genreAlbums[b]!.length.compareTo(genreAlbums[a]!.length);
        return countCmp != 0 ? countCmp : a.compareTo(b);
      });
    return LibraryGenreIndex(
      albumGenres: albumGenres,
      genreAlbums: genreAlbums,
      genres: genres,
    );
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
