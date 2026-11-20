part of '../library_controller.dart';

extension _LibraryControllerLoading on LibraryController {
  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    _isLoading = true;
    _error = null;
    _notifyListeners();
    try {
      await _loadPreferences(client);
      if (!identical(client, _client)) return;
      final hadSnapshot = await _loadSnapshot(
        _preferencesKey,
        expectedClient: client,
        offline: false,
      );
      if (!identical(client, _client)) return;

      if (hadSnapshot) {
        _prewarmPriorityArtwork(client);
      }

      // Account-scoped data is not part of the catalog change feed, so it is
      // fetched every load (all four payloads are small).
      final accountFuture = Future.wait<Object?>([
        client.fetchPins(),
        client.fetchPlaylistEditsAndImages(),
        _fetchHiddenOrKeep(client),
        client.fetchArtistImages(),
        _fetchCurationOrKeep(client),
      ]);
      // The catalog path below can throw (or bail on a client swap) before
      // this future is awaited; without a pre-attached handler its failure
      // would surface as an unhandled zone error.
      accountFuture.ignore();

      // Snapshot plus a resume token: try the incremental path first. It
      // replays only what changed since the snapshot was written — usually
      // nothing — instead of refetching the whole catalog on every launch
      // and reconnect.
      var deltaApplied = false;
      if (hadSnapshot && _syncToken > 0) {
        deltaApplied = await _tryApplyChanges(client);
        if (!identical(client, _client)) return;
      }
      if (!deltaApplied) {
        await _runFullCatalogRefresh(client);
        if (!identical(client, _client)) return;
      }

      final accountResults = await accountFuture;
      if (!identical(client, _client)) return;
      final editsPayload = accountResults[1] as ({
        List<PlaylistEdit> edits,
        Map<String, int> imageVersions
      });
      _applyPlaylistImageVersions(editsPayload.imageVersions);
      _applyPlaylistEdits(editsPayload.edits);
      await _replayPendingPlaylistEdits(client);
      await _migrateLegacyPlaylistOverrides(client);
      _applyPins(accountResults[0] as List<PinnedMediaItem>);
      if (accountResults[2] case final List<HiddenMediaItem> hidden) {
        _applyHidden(hidden);
      }
      if (accountResults[3] case final Map<String, int> artistImages) {
        _applyArtistImageVersions(artistImages);
      }
      if (accountResults[4] case final UserLibraryCuration curation) {
        _applyCuration(curation);
      }
      _sortLibrary();
      _prewarmPriorityArtwork(client);
      _warmLibraryThumbnailsInBackground(client);
      _isOfflineSnapshot = false;
      _error = null;
      // Persist the effective library so offline mode can show it next time
      // the app launches without a reachable server.
      await _saveSnapshot();
    } on PlayerApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '$e';
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  /// Hidden items, or null when the server could not answer.
  ///
  /// Hiding is a presentation preference: a server that predates the feature
  /// (or is simply having a bad minute) must not fail the whole library load
  /// over it. Null means "keep what we already had" rather than "nothing is
  /// hidden", so a blip can't flash every hidden album back into the sidebar.
  /// Auth failures still propagate — those the sign-in flow has to see.
  Future<List<HiddenMediaItem>?> _fetchHiddenOrKeep(
    PlayerApiClient client,
  ) async {
    try {
      return await client.fetchHidden();
    } on PlayerApiException catch (e) {
      if (e.isAuthError) rethrow;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<UserLibraryCuration?> _fetchCurationOrKeep(
    PlayerApiClient client,
  ) async {
    try {
      return await client.fetchCuration();
    } on PlayerApiException catch (e) {
      if (e.isAuthError) rethrow;
      return null;
    } catch (_) {
      return null;
    }
  }

  void _clearBootstrapResume() {
    _bootstrapCursor = null;
    _bootstrapMinToken = 0;
    _bootstrapAlbums.clear();
    _bootstrapSongs.clear();
    _bootstrapPlaylists.clear();
  }

  /// Replaces the in-memory catalog from `/v2/bootstrap` (one interleaved,
  /// cursor-resumable feed that also yields the change-feed resume token).
  /// Servers without the endpoint fall back to the three legacy list
  /// endpoints.
  Future<void> _runFullCatalogRefresh(PlayerApiClient client) async {
    if (!identical(_bootstrapResumeClient, client)) {
      _clearBootstrapResume();
      _bootstrapResumeClient = client;
    }
    try {
      var guard = 0;
      while (true) {
        final page = await client.fetchBootstrapPage(cursor: _bootstrapCursor);
        if (!identical(client, _client)) return;
        for (final album in page.albums) {
          _bootstrapAlbums[album.id] = album;
        }
        for (final song in page.songs) {
          _bootstrapSongs[song.id] = song;
        }
        for (final playlist in page.playlists) {
          _bootstrapPlaylists[playlist.id] = playlist;
        }
        // The minimum token across pages is the safe delta resume point:
        // anything committed after it gets replayed by /v2/changes, and
        // replaying an upsert twice is harmless. (Taking the last page's
        // token could skip changes made to early pages mid-bootstrap.)
        if (_bootstrapMinToken == 0 || page.syncToken < _bootstrapMinToken) {
          _bootstrapMinToken = page.syncToken;
        }
        final nextCursor = page.nextCursor;
        if (!page.hasMore ||
            nextCursor == null ||
            nextCursor.isEmpty ||
            nextCursor == _bootstrapCursor) {
          break;
        }
        // Advanced only after the page applied, so a thrown request leaves
        // the cursor at the last completed page for the next attempt.
        _bootstrapCursor = nextCursor;
        if (++guard > 10000) break;
      }
      _albums = _bootstrapAlbums.values.toList();
      _songs = hydrateTrackAlbumMetadata(_bootstrapSongs.values, _albums);
      _basePlaylists = _bootstrapPlaylists.values.toList();
      _albumDetailCache.clear();
      _syncToken = _bootstrapMinToken;
      final caughtUp = await _tryApplyChanges(client);
      if (!identical(client, _client)) return;
      if (!caughtUp) {
        throw PlayerApiException(
          'CATALOG_SYNC_FAILED',
          'Could not catch up catalog changes after bootstrap',
        );
      }
      _clearBootstrapResume();
      return;
    } on PlayerApiException catch (error) {
      final endpointMissing =
          error.statusCode == 404 || error.code == 'NOT_FOUND';
      if (_bootstrapCursor != null || !endpointMissing) {
        if (_bootstrapCursor == null) {
          // A single-page bootstrap has no resumable cursor. Discard its
          // staged maps so the next attempt starts from a clean snapshot.
          _clearBootstrapResume();
        }
        // Mid-bootstrap failure: keep the staged pages and cursor so the
        // next load resumes instead of restarting. First-page transient,
        // authentication, and server errors also surface rather than
        // multiplying traffic with three legacy catalog requests.
        rethrow;
      }
      // A server without the complete v2 catalog-sync surface uses the
      // legacy catalog endpoints.
      _clearBootstrapResume();
    }

    client.resetCatalogSyncTokenCapture();
    final results = await Future.wait([
      client.fetchAllAlbums(),
      client.fetchAllSongs(),
      client.fetchPlaylists(),
    ]);
    if (!identical(client, _client)) return;
    _albums = results[0] as List<Album>;
    _songs = hydrateTrackAlbumMetadata(
      results[1] as List<Track>,
      _albums,
    );
    _basePlaylists = results[2] as List<PlaylistSummary>;
    _albumDetailCache.clear();
    _syncToken = client.capturedCatalogSyncToken ?? 0;
  }

  /// Replays `/v2/changes` since [_syncToken] onto the in-memory catalog.
  ///
  /// Returns false whenever the feed cannot be trusted to reconstruct the
  /// catalog — old server (404), server reset (our token is ahead of the
  /// server's), an upsert without an inline payload (mobile's bootstrap
  /// signal), or any error — in which case the caller falls back to the full
  /// refetch. Playlist membership events are not applied positionally;
  /// any playlist change triggers one cheap `/v2/playlists` refetch instead.
  Future<bool> _tryApplyChanges(PlayerApiClient client) async {
    try {
      var since = _syncToken;
      var playlistsDirty = false;
      var catalogDirty = false;
      final albumsById = <String, Album>{
        for (final album in _albums) album.id: album,
      };
      final songsById = <String, Track>{
        for (final song in _songs) song.id: song,
      };

      var guard = 0;
      while (true) {
        final page = await client.fetchChangesSince(since);
        if (!identical(client, _client)) return false;
        // A server whose latest token is behind ours was rebuilt from
        // scratch; our token no longer means anything.
        if (page.syncToken < since) return false;

        for (final event in page.events) {
          if (event.token <= since) continue;
          switch (event.entityType) {
            case 'album':
              if (event.isUpsert) {
                final payload = event.payload;
                if (payload == null) return false;
                albumsById[event.entityId] = Album.fromJson(payload);
                catalogDirty = true;
              } else if (event.isDelete) {
                catalogDirty |= albumsById.remove(event.entityId) != null;
              }
            case 'song':
              if (event.isUpsert) {
                final payload = event.payload;
                if (payload == null) return false;
                songsById[event.entityId] = Track.fromJson(payload);
                catalogDirty = true;
              } else if (event.isDelete) {
                catalogDirty |= songsById.remove(event.entityId) != null;
              }
            case 'playlist':
            case 'playlist_song':
              playlistsDirty = true;
            default:
              // Unknown entity types (e.g. artwork) don't affect the
              // in-memory catalog.
              break;
          }
        }

        since = page.toToken > since ? page.toToken : since;
        if (!page.hasMore) break;
        if (++guard > 1000) return false;
      }

      if (playlistsDirty) {
        _basePlaylists = await client.fetchPlaylists();
        if (!identical(client, _client)) return false;
      }
      if (catalogDirty) {
        _albums = albumsById.values.toList();
        _songs = hydrateTrackAlbumMetadata(songsById.values, _albums);
        _albumDetailCache.clear();
      }
      if (playlistsDirty) {
        _reapplyPlaylistEdits();
      }
      _syncToken = since;
      return true;
    } catch (_) {
      // Includes 404 from servers without the change feed. The caller's full
      // refetch either succeeds or produces the user-facing error.
      return false;
    }
  }

  /// Entry point for the server's `sync_token_advanced` WebSocket push.
  ///
  /// Debounced: library scans emit bursts of token advances. Runs the same
  /// incremental path as [load], falling back to a full [load] when the feed
  /// cannot be replayed.
  void _onSyncTokenAdvanced(int latestToken) {
    if (_client == null || _isOfflineSnapshot) return;
    if (latestToken > 0 && latestToken <= _syncToken) return;
    _pendingSyncTarget =
        latestToken > _pendingSyncTarget ? latestToken : _pendingSyncTarget;
    _syncTokenDebounce?.cancel();
    _syncTokenDebounce = Timer(syncTokenDebounceDuration, () {
      unawaited(_runDeltaSync());
    });
  }

  Future<void> _runDeltaSync() async {
    final client = _client;
    if (client == null) return;
    if (_isLoading) {
      // A full load is running (possibly slowly, over the very connection
      // this sync exists for). Re-arm instead of dropping the notification:
      // a token pushed after load() read the change feed would otherwise
      // leave the library stale until the next push.
      _syncTokenDebounce?.cancel();
      _syncTokenDebounce = Timer(syncTokenDebounceDuration, () {
        unawaited(_runDeltaSync());
      });
      return;
    }
    if (_deltaSyncInFlight) {
      // A push arrived mid-sync; the finishing run re-checks the target.
      return;
    }
    _deltaSyncInFlight = true;
    try {
      final target = _pendingSyncTarget;
      if (_syncToken <= 0) {
        // Nothing to resume from (old server or never fully loaded).
        await load();
        return;
      }
      final applied = await _tryApplyChanges(client);
      if (!identical(client, _client)) return;
      if (!applied) {
        await load();
        return;
      }
      _sortLibrary();
      _notifyListeners();
      await _saveSnapshot();
      if (_pendingSyncTarget > target && _pendingSyncTarget > _syncToken) {
        // Another push arrived while syncing; catch up once more.
        _syncTokenDebounce?.cancel();
        _syncTokenDebounce = Timer(syncTokenDebounceDuration, () {
          unawaited(_runDeltaSync());
        });
      }
    } finally {
      _deltaSyncInFlight = false;
    }
  }

  ({Set<String> albumIds, Set<String> songIds, Set<String> customUrls})
      _priorityArtworkTargets(PlayerApiClient client) {
    final albumIds = <String>{};
    final songIds = <String>{};
    final customUrls = <String>{};
    if (_albums.isEmpty && _playlists.isEmpty) {
      return (albumIds: albumIds, songIds: songIds, customUrls: customUrls);
    }

    for (final pl in _playlists.take(12)) {
      final imageVersion = _playlistImageVersions[pl.id];
      if (imageVersion != null) {
        customUrls.add(ArtworkImageProvider.sizedUrl(
          client.playlistImageUrl(pl.id, version: imageVersion),
          640,
        ));
      } else {
        for (final track in _playlistCoverTracks(pl)) {
          if (track.albumId != null && track.albumId!.isNotEmpty) {
            albumIds.add(track.albumId!);
          } else if (track.id.isNotEmpty) {
            songIds.add(track.id);
          }
        }
      }
    }

    for (final album in _albums.take(24)) {
      if (album.id.isNotEmpty) {
        albumIds.add(album.id);
      }
    }

    return (albumIds: albumIds, songIds: songIds, customUrls: customUrls);
  }

  Set<String> _priorityArtworkUrls(PlayerApiClient client) {
    final t = _priorityArtworkTargets(client);
    return <String>{
      ...t.customUrls,
      for (final id in t.albumIds) client.albumArtworkUrl(id, thumbnail: true),
      for (final id in t.songIds) client.songArtworkUrl(id, thumbnail: true),
    };
  }

  /// Fills the persistent artwork cache with priority covers in 1-2 batch calls.
  void _prewarmPriorityArtwork(PlayerApiClient client) {
    if (ArtworkImageProvider.cacheStore == null) return;
    final targets = _priorityArtworkTargets(client);
    if (targets.albumIds.isNotEmpty || targets.songIds.isNotEmpty) {
      unawaited(
        ArtworkImageProvider.prefetchBatch(
          client,
          albumIds: targets.albumIds,
          songIds: targets.songIds,
          background: true,
        ),
      );
    }
    if (targets.customUrls.isEmpty) return;
    unawaited(() async {
      for (final url in targets.customUrls) {
        if (!identical(client, _client)) break;
        try {
          await ArtworkImageProvider.loadBytes(
            url,
            headers: client.artworkHeaders,
            background: true,
          );
        } catch (_) {}
      }
    }());
  }

  /// Gently warms remaining album thumbnails into the persistent cache (e.g.
  /// IndexedDB on web) in chunks of 40 so later searches hit locally at 0ms.
  void _warmLibraryThumbnailsInBackground(PlayerApiClient client) {
    if (ArtworkImageProvider.cacheStore == null || _albums.isEmpty) return;
    final generation = ++_backgroundWarmGeneration;
    final albumIds = [
      for (final album in _albums)
        if (album.id.isNotEmpty) album.id,
    ];
    if (albumIds.isEmpty) return;

    const maxWarmAlbums = 2000;
    const chunkSize = 40;
    final capped = albumIds.length > maxWarmAlbums
        ? albumIds.sublist(0, maxWarmAlbums)
        : albumIds;

    unawaited(() async {
      await Future<void>.delayed(const Duration(seconds: 5));
      for (var i = 0; i < capped.length; i += chunkSize) {
        if (!identical(client, _client) ||
            generation != _backgroundWarmGeneration) {
          return;
        }
        while (ArtworkImageProvider.hasForegroundActivity) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (!identical(client, _client) ||
              generation != _backgroundWarmGeneration) {
            return;
          }
        }
        final end =
            (i + chunkSize) < capped.length ? (i + chunkSize) : capped.length;
        try {
          await ArtworkImageProvider.prefetchBatch(
            client,
            albumIds: capped.sublist(i, end),
            background: true,
          );
        } catch (_) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }());
  }
}
