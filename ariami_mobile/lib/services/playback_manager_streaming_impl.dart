part of 'playback_manager.dart';

/// Total time a streamed song may spend starting up (stream ticket + player
/// load) when an on-device copy exists to fall back to. A network that looks
/// connected but has no internet (Wi-Fi while walking out the door) hangs
/// here long before the 30s heartbeat notices.
const _streamStartStallTimeout = Duration(seconds: 8);

/// Minimum slice of the stall budget any single startup step is given.
const _minStreamStartGrace = Duration(seconds: 1);

extension _PlaybackManagerStreamingImpl on PlaybackManager {
  Future<void> _playCurrentSongImpl({
    bool autoPlay = true,
    bool restartStatsTracking = true,
    bool isResume = false,
    bool forceOfflineSource = false,
  }) async {
    print('[PlaybackManager] _playCurrentSong() called');

    // Starting a fresh track resets any pending silence-pause state.
    _pausedBySilence = false;

    final queuedSong = _queue.currentSong;
    if (queuedSong == null) {
      print('[PlaybackManager] ERROR: No current song in queue!');
      return;
    }

    // SongModel stores albumId as the normalized catalog source of truth, but
    // many queue/playback entry points do not carry the denormalized title.
    // Enrich once at the playback boundary so stats, notifications and saved
    // playback state all receive the same album metadata.
    final song = await _resolveAlbumMetadata(queuedSong);
    _replaceQueuedSongMetadata(queuedSong, song);

    print('[PlaybackManager] Current song: ${song.title}');

    if (_castService.isConnected) {
      try {
        final casted = await _castService.syncFromPlayback(
          song: song,
          position: _restoredPosition ?? Duration.zero,
          isPlaying: autoPlay,
          force: true,
        );
        if (casted) {
          await _audioPlayer.pauseLocal();
          _enterCastNotificationMode(song, autoPlay);
          _restoredPosition = null;
          _pendingUiPosition = null;
          if (restartStatsTracking) {
            _statsService.onSongStarted(song, isResume: isResume);
          }
          ColorExtractionService().extractColorsForSong(song);
          _notifyStateChanged();
          return;
        }
      } catch (e) {
        print('[PlaybackManager] Cast sync failed, falling back to local: $e');
      }
    }

    try {
      // Determine playback source (local file or stream)
      final playbackSource = forceOfflineSource
          ? await _offlineService.getOfflineFallbackSource(song.id)
          : await _offlineService.getPlaybackSource(song.id);
      print('[PlaybackManager] Playback source: $playbackSource'
          '${forceOfflineSource ? ' (forced offline fallback)' : ''}');

      String audioUrl;
      Uri? artworkUri;

      // Set while starting a stream for a song that also exists on disk:
      // stream startup steps are capped by this deadline and fall back to the
      // on-device copy instead of hanging on a dead network.
      DateTime? offlineFallbackDeadline;

      switch (playbackSource) {
        case PlaybackSource.local:
          // Use local downloaded file (protected)
          final localPath = _offlineService.getLocalFilePath(song.id);
          if (localPath == null) {
            throw Exception('Local file path not found for downloaded song');
          }
          audioUrl = 'file://$localPath';
          print('[PlaybackManager] Playing from downloaded file: $audioUrl');

          // Get cached artwork for offline playback (with thumbnail fallback)
          final localPrimaryKey = song.albumId ?? 'song_${song.id}';
          final localFallbackKey =
              song.albumId != null ? '${song.albumId}_thumb' : null;
          final cachedArtworkPath = await _cacheManager
              .getArtworkPathWithFallback(localPrimaryKey, localFallbackKey);
          if (cachedArtworkPath != null) {
            artworkUri = Uri.file(cachedArtworkPath);
            print('[PlaybackManager] Using cached artwork: $artworkUri');
          }
          break;

        case PlaybackSource.cached:
          // Use cached file (auto-cached from previous playback)
          final cachedPath = await _offlineService.getCachedFilePath(song.id);
          if (cachedPath == null) {
            throw Exception('Cached file path not found');
          }
          audioUrl = 'file://$cachedPath';
          print('[PlaybackManager] Playing from cached file: $audioUrl');

          // Get cached artwork for offline playback (with thumbnail fallback)
          final cachedPrimaryKey = song.albumId ?? 'song_${song.id}';
          final cachedFallbackKey =
              song.albumId != null ? '${song.albumId}_thumb' : null;
          final cachedArtworkPathForCached = await _cacheManager
              .getArtworkPathWithFallback(cachedPrimaryKey, cachedFallbackKey);
          if (cachedArtworkPathForCached != null) {
            artworkUri = Uri.file(cachedArtworkPathForCached);
            print('[PlaybackManager] Using cached artwork: $artworkUri');
          }
          break;

        case PlaybackSource.stream:
          // Stream from server
          print('[PlaybackManager] Checking connection...');
          if (_connectionService.apiClient == null) {
            print(
                '[PlaybackManager] ERROR: Not connected to server! apiClient is null');
            throw Exception('Not connected to server');
          }
          print(
              '[PlaybackManager] Connected! Base URL: ${_connectionService.apiClient!.baseUrl}');

          // Get streaming quality based on current network (WiFi vs mobile data)
          final streamingQuality = _qualityService.getCurrentStreamingQuality();

          if (await _offlineService.getOfflineFallbackSource(song.id) !=
              PlaybackSource.unavailable) {
            offlineFallbackDeadline =
                DateTime.now().add(_streamStartStallTimeout);
          }

          // Get stream URL (with retry-once logic for expired tokens)
          try {
            audioUrl = await _capByOfflineFallbackDeadline(
              _getStreamUrlWithRetry(song, streamingQuality),
              offlineFallbackDeadline,
            );
          } catch (e) {
            if (offlineFallbackDeadline == null) {
              // The server no longer has this song (stale playlist/queue id)
              // and there is no on-device copy: it can never play, so skip
              // past it instead of stalling here.
              if (e is ApiException && e.isCode(ApiErrorCodes.songNotFound)) {
                print('[PlaybackManager] Song not on server (${song.id}), '
                    'auto-skipping unplayable entry');
                await _skipUnplayableSong(
                  song,
                  autoPlay: autoPlay,
                  restartStatsTracking: restartStatsTracking,
                );
                return;
              }
              rethrow;
            }
            print('[PlaybackManager] Stream ticket stalled/failed ($e), '
                'falling back to on-device copy');
            await _fallBackToOfflineCopy(
              autoPlay: autoPlay,
              restartStatsTracking: restartStatsTracking,
              isResume: isResume,
            );
            return;
          }
          print(
              '[PlaybackManager] Streaming from server: $audioUrl (quality: ${streamingQuality.name})');

          // Use server URL for artwork when streaming
          if (song.albumId != null) {
            artworkUri = Uri.parse(
                '${_connectionService.apiClient!.baseUrl}/artwork/${song.albumId}');
          } else {
            // Standalone song - use song artwork endpoint
            artworkUri = Uri.parse(
                '${_connectionService.apiClient!.baseUrl}/song-artwork/${song.id}');
          }

          // Notification artwork loaders cannot attach Authorization headers.
          // In authenticated mode, pass streamToken in the artwork URL.
          if (_connectionService.isAuthenticated) {
            final streamToken = _extractStreamToken(audioUrl);
            if (streamToken != null && streamToken.isNotEmpty) {
              artworkUri = artworkUri.replace(
                queryParameters: {'streamToken': streamToken},
              );
            }
          }
          print('[PlaybackManager] Using server artwork: $artworkUri');

          // Whole-file media caching is deliberately Wi-Fi-only. On cellular a
          // high/original cache download otherwise competes with the lower-rate
          // stream the listener is waiting for.
          if (_qualityService.allowsSpeculativeMediaDownloads) {
            _cacheFullArtworkInBackground(song, artworkUri);
            _cacheSongInBackground(song);
          }
          _warmNextStreamInBackground(streamingQuality);
          break;

        case PlaybackSource.unavailable:
          print(
              '[PlaybackManager] Song not available offline, searching for next available song...');
          // Try to find and play the next available song
          final nextAvailableIndex = await _findNextAvailableSongIndex();
          if (nextAvailableIndex != null) {
            print(
                '[PlaybackManager] Found available song at index $nextAvailableIndex, skipping to it');
            _queue.jumpToIndex(nextAvailableIndex);
            await _playCurrentSong(); // Recursive call to play the available song
          } else {
            // No songs available, stop playback
            print(
                '[PlaybackManager] No available songs in queue, stopping playback');
            await _audioPlayer.stop();
            _notifyStateChanged();
          }
          return; // Don't continue with playback logic
      }

      // If we have a restored position, load without playing, seek, then play
      final shouldDeferGaplessPreparation =
          playbackSource == PlaybackSource.stream &&
              !_qualityService.allowsSpeculativeMediaDownloads;
      // Preparing the next track may request a stream ticket; never let that
      // stall the song the listener actually picked (it degrades to non-
      // gapless when it can't resolve in time).
      final upcoming = shouldDeferGaplessPreparation
          ? null
          : await _resolveNextGaplessItem(song).timeout(
              _streamStartStallTimeout,
              onTimeout: () => null,
            );
      _deferredGaplessSongId =
          shouldDeferGaplessPreparation && _gaplessPlayback.isEnabled
              ? song.id
              : null;
      try {
        if (_restoredPosition != null) {
          // Load the song WITHOUT starting playback
          await _capByOfflineFallbackDeadline(
            _audioPlayer.loadSong(
              song,
              audioUrl,
              artworkUri: artworkUri,
              upcoming: upcoming,
            ),
            offlineFallbackDeadline,
          );

          // Wait for the audio player to be fully ready before seeking
          await Future.delayed(const Duration(milliseconds: 500));

          // Seek to the restored position BEFORE starting playback
          await _audioPlayer.seek(_restoredPosition!);

          // Notify listeners so UI updates with the new position
          _notifyStateChanged();

          // NOW start playback from the seeked position
          if (autoPlay) {
            await _audioPlayer.resume();
          }

          _restoredPosition = null; // Clear so it doesn't affect next song
        } else {
          if (autoPlay) {
            // No restored position - play normally from the beginning
            await _capByOfflineFallbackDeadline(
              _audioPlayer.playSong(
                song,
                audioUrl,
                artworkUri: artworkUri,
                upcoming: upcoming,
              ),
              offlineFallbackDeadline,
            );
          } else {
            await _capByOfflineFallbackDeadline(
              _audioPlayer.loadSong(
                song,
                audioUrl,
                artworkUri: artworkUri,
                upcoming: upcoming,
              ),
              offlineFallbackDeadline,
            );
          }
        }
      } on TimeoutException {
        if (offlineFallbackDeadline == null) rethrow;
        print('[PlaybackManager] Stream load stalled past '
            '${_streamStartStallTimeout.inSeconds}s, '
            'falling back to on-device copy');
        await _fallBackToOfflineCopy(
          autoPlay: autoPlay,
          restartStatsTracking: restartStatsTracking,
          isResume: isResume,
        );
        return;
      }

      _unplayableSkipStreak = 0;

      // Track stats for this song playback
      if (restartStatsTracking) {
        print(
            '[PlaybackManager] About to call onSongStarted for: ${song.title}');
        _statsService.onSongStarted(song, isResume: isResume);
        print('[PlaybackManager] onSongStarted called successfully');
      }

      // Extract colors from artwork for player gradient background
      ColorExtractionService().extractColorsForSong(song);
    } catch (e, stackTrace) {
      print('[PlaybackManager] ERROR in _playCurrentSong: $e');
      print('[PlaybackManager] Stack trace: $stackTrace');
      // Legacy mode and older servers issue stream URLs without checking the
      // library, so a deleted song only fails here at player-load time. When
      // the synced local library confirms the id no longer exists, skip it
      // instead of halting the queue on an unplayable entry.
      if (await _isSongGoneFromLibrary(song.id)) {
        print('[PlaybackManager] Song ${song.id} confirmed gone from library, '
            'auto-skipping unplayable entry');
        await _skipUnplayableSong(
          song,
          autoPlay: autoPlay,
          restartStatsTracking: restartStatsTracking,
        );
        return;
      }
      rethrow;
    }
  }

  /// True only when the synced local library can positively confirm the song
  /// id no longer exists. Stays false offline or before the first library
  /// bootstrap, so genuine network errors keep their existing behavior.
  Future<bool> _isSongGoneFromLibrary(String songId) async {
    if (_offlineService.isOffline) return false;
    try {
      if (!await _libraryRepository.hasCompletedBootstrap()) return false;
      return await _libraryRepository.getSongById(songId) == null;
    } catch (_) {
      return false;
    }
  }

  /// Skips past a song that can never play (deleted from the server library),
  /// notifying the UI which track was skipped. The streak cap stops the chain
  /// once every remaining queue entry has been tried, so a queue made entirely
  /// of stale ids halts instead of cycling forever under repeat-all.
  Future<void> _skipUnplayableSong(
    Song song, {
    required bool autoPlay,
    required bool restartStatsTracking,
  }) async {
    _unplayableSongController.add(song);
    _unplayableSkipStreak++;

    final exhaustedQueue = _unplayableSkipStreak >= _queue.length;
    final int? nextIndex;
    if (exhaustedQueue) {
      nextIndex = null;
    } else if (_queue.hasNext) {
      nextIndex = _queue.currentIndex + 1;
    } else if (_repeatMode == RepeatMode.all && _queue.length > 1) {
      nextIndex = 0;
    } else {
      nextIndex = null;
    }

    if (nextIndex == null) {
      print('[PlaybackManager] No playable song to skip to, stopping playback');
      _unplayableSkipStreak = 0;
      await _audioPlayer.stop();
      _notifyStateChanged();
      await _saveState();
      return;
    }

    _queue.jumpToIndex(nextIndex);
    _restoredPosition = null;
    _pendingUiPosition = null;
    _notifyStateChanged();
    await _playCurrentSongImpl(
      autoPlay: autoPlay,
      restartStatsTracking: restartStatsTracking,
    );
    _notifyStateChanged();
    await _saveState();
  }

  /// Caps a stream-startup step by the shared stall deadline, or passes the
  /// future through untouched when no on-device fallback exists.
  Future<T> _capByOfflineFallbackDeadline<T>(
    Future<T> future,
    DateTime? deadline,
  ) {
    if (deadline == null) return future;
    var remaining = deadline.difference(DateTime.now());
    if (remaining < _minStreamStartGrace) remaining = _minStreamStartGrace;
    return future.timeout(remaining);
  }

  /// Replays the current song from its downloaded/cached copy after stream
  /// startup stalled, and probes the connection in the background so a truly
  /// dead network flips the whole app into auto-offline mode promptly instead
  /// of waiting for the periodic heartbeat.
  Future<void> _fallBackToOfflineCopy({
    required bool autoPlay,
    required bool restartStatsTracking,
    required bool isResume,
  }) async {
    unawaited(_connectionService.verifyConnectionNow());
    await _playCurrentSongImpl(
      autoPlay: autoPlay,
      restartStatsTracking: restartStatsTracking,
      isResume: isResume,
      forceOfflineSource: true,
    );
  }

  Future<Song> _resolveAlbumMetadata(Song song) async {
    if (song.albumId == null || song.albumId!.trim().isEmpty) return song;
    if ((song.album?.trim().isNotEmpty ?? false) &&
        (song.albumArtist?.trim().isNotEmpty ?? false)) {
      return song;
    }

    final album = await AlbumMetadataResolver().resolve(song.albumId);
    if (album == null) return song;
    return song.copyWith(
      album: song.album?.trim().isNotEmpty == true ? song.album : album.title,
      albumArtist: song.albumArtist?.trim().isNotEmpty == true
          ? song.albumArtist
          : album.artist,
    );
  }

  void _replaceQueuedSongMetadata(Song expected, Song replacement) {
    if (identical(expected, replacement) ||
        _queue.currentSong?.id != expected.id ||
        _queue.currentIndex < 0 ||
        _queue.currentIndex >= _queue.length) {
      return;
    }
    final songs = List<Song>.from(_queue.songs);
    songs[_queue.currentIndex] = replacement;
    _queue = PlaybackQueue(
      songs: songs,
      currentIndex: _queue.currentIndex,
    );
  }

  Future<GaplessPlaybackItem?> _resolveNextGaplessItem(
    Song expectedCurrentSong,
  ) async {
    if (!_gaplessPlayback.isEnabled ||
        _castService.isConnected ||
        _repeatMode == RepeatMode.one ||
        _queue.currentSong?.id != expectedCurrentSong.id) {
      return null;
    }

    int? nextIndex;
    if (_queue.hasNext) {
      nextIndex = await _findNextAvailableSongIndex();
    } else if (_repeatMode == RepeatMode.all && _queue.length > 1) {
      nextIndex = await _findNextAvailableSongIndexFrom(0);
    }
    if (nextIndex == null ||
        _queue.currentSong?.id != expectedCurrentSong.id ||
        nextIndex < 0 ||
        nextIndex >= _queue.length) {
      return null;
    }

    return _resolveGaplessItem(_queue.songs[nextIndex]);
  }

  Future<GaplessPlaybackItem?> _resolveGaplessItem(Song song) async {
    try {
      // Gapless tracks bypass _playCurrentSong at the transition boundary, so
      // they must carry the same resolved metadata into the prepared item.
      song = await _resolveAlbumMetadata(song);
      final source = await _offlineService.getPlaybackSource(song.id);
      String streamUrl;
      Uri? artworkUri;

      switch (source) {
        case PlaybackSource.local:
          final path = _offlineService.getLocalFilePath(song.id);
          if (path == null) return null;
          streamUrl = 'file://$path';
          break;
        case PlaybackSource.cached:
          final path = await _offlineService.getCachedFilePath(song.id);
          if (path == null) return null;
          streamUrl = 'file://$path';
          break;
        case PlaybackSource.stream:
          if (_connectionService.apiClient == null) return null;
          final quality = _qualityService.getCurrentStreamingQuality();
          streamUrl = await _getStreamUrlWithRetry(song, quality);

          final baseUrl = _connectionService.apiClient!.baseUrl;
          artworkUri = song.albumId != null
              ? Uri.parse('$baseUrl/artwork/${song.albumId}')
              : Uri.parse('$baseUrl/song-artwork/${song.id}');
          if (_connectionService.isAuthenticated) {
            final token = _extractStreamToken(streamUrl);
            if (token != null && token.isNotEmpty) {
              artworkUri = artworkUri.replace(
                queryParameters: {'streamToken': token},
              );
            }
          }
          break;
        case PlaybackSource.unavailable:
          return null;
      }

      if (source == PlaybackSource.local || source == PlaybackSource.cached) {
        final primaryKey = song.albumId ?? 'song_${song.id}';
        final fallbackKey =
            song.albumId != null ? '${song.albumId}_thumb' : null;
        final artworkPath = await _cacheManager.getArtworkPathWithFallback(
          primaryKey,
          fallbackKey,
        );
        if (artworkPath != null) artworkUri = Uri.file(artworkPath);
      }

      return GaplessPlaybackItem(
        song: song,
        streamUrl: streamUrl,
        artworkUri: artworkUri,
      );
    } catch (e) {
      debugPrint(
        '[PlaybackManager] Could not prepare gapless source for ${song.title}: $e',
      );
      return null;
    }
  }

  Future<void> _refreshGaplessQueueImpl() async {
    final generation = ++_gaplessRefreshGeneration;
    final current = _queue.currentSong;
    if (current == null || _castService.isConnected) return;

    if (!_qualityService.allowsSpeculativeMediaDownloads &&
        !hasSpeculativeGaplessHeadroom(
          position: _audioPlayer.position,
          bufferedPosition: _audioPlayer.bufferedPosition,
          duration: _audioPlayer.duration,
        )) {
      _deferredGaplessSongId = current.id;
      return;
    }
    _deferredGaplessSongId = null;

    final upcoming = await _resolveNextGaplessItem(current);
    if (generation != _gaplessRefreshGeneration ||
        _queue.currentSong?.id != current.id) {
      return;
    }
    await _audioPlayer.setUpcomingGaplessItem(current, upcoming);
  }

  Future<void> _handleGaplessTransitionImpl(
    GaplessPlaybackTransition transition,
  ) async {
    if (_isHandlingGaplessTransition ||
        !_gaplessPlayback.isEnabled ||
        _castService.isConnected ||
        _queue.currentSong?.id != transition.previousSong.id) {
      return;
    }

    int? nextIndex;
    if (_queue.hasNext) {
      nextIndex = await _findNextAvailableSongIndex();
    } else if (_repeatMode == RepeatMode.all && _queue.length > 1) {
      nextIndex = await _findNextAvailableSongIndexFrom(0);
    }
    if (nextIndex == null ||
        nextIndex < 0 ||
        nextIndex >= _queue.length ||
        _queue.songs[nextIndex].id != transition.currentSong.id) {
      // The queue changed while an old source was crossing the boundary.
      // Load the queue's actual next item instead of publishing stale state.
      if (_queue.currentSong?.id == transition.previousSong.id) {
        await _skipNextImpl(completedNaturally: true);
      }
      return;
    }

    _isHandlingGaplessTransition = true;
    try {
      final previousIndex = _queue.currentIndex;
      final previousSong = _queue.currentSong;
      final currentSong = await _resolveAlbumMetadata(transition.currentSong);
      final stopStats = _statsService.onSongStopped(completedNaturally: true);
      _queue.jumpToIndex(nextIndex);
      _replaceQueuedSongMetadata(_queue.currentSong!, currentSong);
      _consumeOneShotQueueItem(previousIndex, previousSong);
      _restoredPosition = null;
      _pendingUiPosition = null;
      _notifyStateChanged();

      await stopStats;
      _statsService.onSongStarted(currentSong);
      ColorExtractionService().extractColorsForSong(currentSong);
      await _saveState();
      await _refreshGaplessQueue();
    } catch (e, stackTrace) {
      debugPrint('[PlaybackManager] Gapless transition failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isHandlingGaplessTransition = false;
    }
  }

  void _cacheSongInBackgroundImpl(Song song) async {
    if (_connectionService.apiClient == null ||
        !_qualityService.allowsSpeculativeMediaDownloads) {
      return;
    }

    final apiClient = _connectionService.apiClient!;
    final downloadQuality = _qualityService.getDownloadQuality();
    final downloadMode = _qualityService.getDownloadOriginal()
        ? 'original'
        : downloadQuality.name;

    String downloadUrl;

    // Use authenticated download URL if authenticated, otherwise use legacy URL
    if (_connectionService.isAuthenticated) {
      try {
        // Request a stream ticket for the download
        final qualityParam = downloadQuality != StreamingQuality.high
            ? downloadQuality.toApiParam()
            : null;
        final ticketResponse = await apiClient.getStreamTicket(
          song.id,
          quality: qualityParam,
        );
        downloadUrl = apiClient.getDownloadUrlWithToken(
          song.id,
          ticketResponse.streamToken,
          quality: downloadQuality,
        );
      } catch (e) {
        print('[PlaybackManager] Failed to get stream ticket for caching: $e');
        return;
      }
    } else {
      // Legacy mode - use direct download URL
      final baseDownloadUrl = apiClient.getDownloadUrl(song.id);
      downloadUrl = _qualityService.getDownloadUrlWithQuality(baseDownloadUrl);
    }

    // Trigger background cache (non-blocking)
    unawaited(() async {
      try {
        final started = await _cacheManager.cacheSong(song.id, downloadUrl);
        if (started) {
          print(
              '[PlaybackManager] Started background caching for: ${song.title} (mode: $downloadMode)');
        }
      } catch (e) {
        print('[PlaybackManager] Failed to start background cache: $e');
      }
    }());
  }

  void _cacheFullArtworkInBackground(Song song, Uri? artworkUri) {
    if (artworkUri == null) return;

    final cacheKey = song.albumId ?? 'song_${song.id}';
    final artworkUrl = artworkUri.toString();

    unawaited(() async {
      try {
        final cachedPath = await _cacheManager.cacheArtwork(
          cacheKey,
          artworkUrl,
          priority: MediaRequestPriority.nearby,
        );
        if (cachedPath != null) {
          debugPrint(
              '[PlaybackManager] Cached full artwork for: ${song.title}');
        }
      } catch (e) {
        debugPrint('[PlaybackManager] Failed to cache full artwork: $e');
      }
    }());
  }

  Future<String> _getStreamUrlWithRetryImpl(
    Song song,
    StreamingQuality quality,
  ) async {
    final apiClient = _connectionService.apiClient!;

    // Legacy mode - direct stream URL (no token needed)
    if (!_connectionService.isAuthenticated) {
      return apiClient.getStreamUrlWithQuality(song.id, quality);
    }

    // Authenticated mode - request stream ticket with retry logic
    final qualityParam =
        quality != StreamingQuality.high ? quality.toApiParam() : null;

    try {
      print(
          '[PlaybackManager] Requesting stream ticket for authenticated streaming...');
      final ticketResponse = await apiClient.getStreamTicket(
        song.id,
        quality: qualityParam,
      );
      print('[PlaybackManager] Got stream ticket, streaming with token');
      return apiClient.getStreamUrlWithToken(
        song.id,
        ticketResponse.streamToken,
        quality: quality,
      );
    } on ApiException catch (e) {
      // Check if token expired - retry once
      if (e.isCode(ApiErrorCodes.streamTokenExpired)) {
        print('[PlaybackManager] Stream token expired, retrying once...');
        final retryTicketResponse = await apiClient.getStreamTicket(
          song.id,
          quality: qualityParam,
        );
        print('[PlaybackManager] Got fresh stream ticket on retry');
        return apiClient.getStreamUrlWithToken(
          song.id,
          retryTicketResponse.streamToken,
          quality: quality,
        );
      }
      // Re-throw other errors
      rethrow;
    }
  }

  String? _extractStreamTokenImpl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return uri.queryParameters['streamToken'];
  }

  void _warmNextStreamInBackgroundImpl(StreamingQuality quality) {
    final nextSong = _queue.nextSong;
    final apiClient = _connectionService.apiClient;
    if (nextSong == null ||
        apiClient == null ||
        !_connectionService.isAuthenticated) {
      return;
    }

    final qualityParam =
        quality != StreamingQuality.high ? quality.toApiParam() : null;
    final key = '${nextSong.id}:${qualityParam ?? 'high'}';
    if (_lastWarmupKey == key) return;
    _lastWarmupKey = key;

    unawaited(() async {
      try {
        final source = await _offlineService.getPlaybackSource(nextSong.id);
        if (source != PlaybackSource.stream) return;
        await apiClient.warmStreams([nextSong.id], quality: qualityParam);
        print('[PlaybackManager] Warmed next stream: ${nextSong.title}');
      } catch (e) {
        print('[PlaybackManager] Failed to warm next stream: $e');
      }
    }());
  }
}
