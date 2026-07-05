part of 'playback_manager.dart';

extension _PlaybackManagerStreamingImpl on PlaybackManager {
  Future<void> _playCurrentSongImpl({
    bool autoPlay = true,
    bool restartStatsTracking = true,
    bool isResume = false,
  }) async {
    print('[PlaybackManager] _playCurrentSong() called');

    // Starting a fresh track resets any pending silence-pause state.
    _pausedBySilence = false;

    final song = _queue.currentSong;
    if (song == null) {
      print('[PlaybackManager] ERROR: No current song in queue!');
      return;
    }

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
      final playbackSource = await _offlineService.getPlaybackSource(song.id);
      print('[PlaybackManager] Playback source: $playbackSource');

      String audioUrl;
      Uri? artworkUri;

      switch (playbackSource) {
        case PlaybackSource.local:
          // Use local downloaded file (protected)
          final localPath = _offlineService.getLocalFilePath(song.id);
          if (localPath == null) {
            throw Exception('Local file path not found for downloaded song');
          }
          // #region agent log
          agentDebugLog(
            location: 'playback_manager.dart:_playCurrentSong',
            message: 'local playback path',
            hypothesisId: 'H5',
            data: {
              'songId': song.id,
              'title': song.title,
              'localPath': localPath,
            },
          );
          // #endregion
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

          // Get stream URL (with retry-once logic for expired tokens)
          audioUrl = await _getStreamUrlWithRetry(song, streamingQuality);
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

          _cacheFullArtworkInBackground(song, artworkUri);

          // Trigger background caching of the song for offline use
          _cacheSongInBackground(song);
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
      final upcoming = await _resolveNextGaplessItem(song);
      if (_restoredPosition != null) {
        // Load the song WITHOUT starting playback
        await _audioPlayer.loadSong(
          song,
          audioUrl,
          artworkUri: artworkUri,
          upcoming: upcoming,
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
          await _audioPlayer.playSong(
            song,
            audioUrl,
            artworkUri: artworkUri,
            upcoming: upcoming,
          );
        } else {
          await _audioPlayer.loadSong(
            song,
            audioUrl,
            artworkUri: artworkUri,
            upcoming: upcoming,
          );
        }
      }

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
      rethrow;
    }
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
      final stopStats = _statsService.onSongStopped(completedNaturally: true);
      _queue.jumpToIndex(nextIndex);
      _consumeOneShotQueueItem(previousIndex, previousSong);
      _restoredPosition = null;
      _pendingUiPosition = null;
      _notifyStateChanged();

      await stopStats;
      _statsService.onSongStarted(transition.currentSong);
      ColorExtractionService().extractColorsForSong(transition.currentSong);
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
    if (_connectionService.apiClient == null) return;

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
