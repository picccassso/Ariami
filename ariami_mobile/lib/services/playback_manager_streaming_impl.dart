part of 'playback_manager.dart';

extension _PlaybackManagerStreamingImpl on PlaybackManager {
  Future<void> _playCurrentSongImpl({
    bool autoPlay = true,
    bool restartStatsTracking = true,
  }) async {
    print('[PlaybackManager] _playCurrentSong() called');

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
          await _audioPlayer.pause();
          _restoredPosition = null;
          _pendingUiPosition = null;
          if (restartStatsTracking) {
            _statsService.onSongStarted(song);
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

          // Trigger background caching of the song for offline use
          _cacheSongInBackground(song);
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
      if (_restoredPosition != null) {
        // Load the song WITHOUT starting playback
        await _audioPlayer.loadSong(song, audioUrl, artworkUri: artworkUri);

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
          await _audioPlayer.playSong(song, audioUrl, artworkUri: artworkUri);
        } else {
          await _audioPlayer.loadSong(song, audioUrl, artworkUri: artworkUri);
        }
      }

      // Track stats for this song playback
      if (restartStatsTracking) {
        print(
            '[PlaybackManager] About to call onSongStarted for: ${song.title}');
        _statsService.onSongStarted(song);
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
}
