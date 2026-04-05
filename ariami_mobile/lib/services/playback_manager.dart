import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import '../models/song.dart';
import '../models/playback_queue.dart';
import '../models/quality_settings.dart';
import '../models/repeat_mode.dart';
import '../models/api_models.dart';
import '../models/download_task.dart';
import 'audio/audio_player_service.dart';
import 'audio/shuffle_service.dart';
import 'audio/playback_state_manager.dart';
import 'api/connection_service.dart';
import 'api/api_client.dart';
import 'download/download_manager.dart';
import 'library/library_repository.dart';
import 'cast/chrome_cast_service.dart';
import 'offline/offline_playback_service.dart';
import 'cache/cache_manager.dart';
import 'stats/streaming_stats_service.dart';
import 'color_extraction_service.dart';
import 'quality/quality_settings_service.dart';
import '../main.dart' show audioHandler;
import '../debug/agent_debug_log.dart';

/// Central playback manager that integrates Phase 6 audio services
/// with Phase 7 UI components. Provides a single source of truth for
/// playback state and controls across the entire app.
class PlaybackManager extends ChangeNotifier {
  // Singleton pattern
  static final PlaybackManager _instance = PlaybackManager._internal();
  factory PlaybackManager() => _instance;
  PlaybackManager._internal();

  // Dependencies
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  final ShuffleService<Song> _shuffleService = ShuffleService<Song>();
  final ConnectionService _connectionService = ConnectionService();
  final PlaybackStateManager _stateManager = PlaybackStateManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final CacheManager _cacheManager = CacheManager();
  final DownloadManager _downloadManager = DownloadManager();
  final LibraryRepository _libraryRepository = LibraryRepository();
  final StreamingStatsService _statsService = StreamingStatsService();
  final QualitySettingsService _qualityService = QualitySettingsService();
  final ChromeCastService _castService = ChromeCastService();

  // State
  PlaybackQueue _queue = PlaybackQueue();
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.none;

  // Stream subscriptions
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription<void>? _skipNextSubscription;
  StreamSubscription<void>? _skipPreviousSubscription;

  // Persistence
  Timer? _saveTimer;
  static const Duration _saveDebounceDuration = Duration(seconds: 5);
  Duration? _restoredPosition; // Position to seek to after restoring state
  Duration?
      _pendingUiPosition; // Temporary UI override for restored seek position
  bool _isInitialized = false;
  int _restoreGeneration = 0;
  bool _isCastTransitionInProgress = false;
  CastMediaPlayerState? _lastObservedCastPlayerState;
  bool _isHandlingCastCompletion = false;

  // Getters
  Song? get currentSong => _queue.currentSong;
  bool get isPlaying => _castService.isConnected
      ? _castService.isRemotePlaying
      : _audioPlayer.isPlaying;
  bool get isLoading => _castService.isConnected
      ? _castService.isRemoteBuffering
      : _audioPlayer.isLoading;
  Duration get position => _castService.isConnected
      ? _castService.remotePosition
      : (_pendingUiPosition ?? _audioPlayer.position);
  Duration? get duration => _castService.isConnected
      ? (_castService.remoteDuration ?? _queue.currentSong?.duration)
      : (_audioPlayer.duration ?? _queue.currentSong?.duration);
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  PlaybackQueue get queue => _queue;
  bool get hasNext => _queue.hasNext;
  bool get hasPrevious => _queue.hasPrevious;
  bool get isCastTransitionInProgress => _isCastTransitionInProgress;

  /// Initialize the playback manager and set up listeners
  void initialize() {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;

    _castService.initialize();
    _castService.addListener(_onCastStateChanged);

    // Listen to position updates
    _positionSubscription = _audioPlayer.positionStream.listen((pos) {
      if (_pendingUiPosition != null && pos >= _pendingUiPosition!) {
        _pendingUiPosition = null;
      }
      notifyListeners();
    });

    // Listen to duration updates
    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        _updateCurrentSongDuration(duration);
      }
      notifyListeners();
    });

    // Listen to player state changes
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      notifyListeners();

      // Auto-advance when song completes
      if (state.processingState.toString() == 'ProcessingState.completed') {
        unawaited(() async {
          try {
            await _onSongCompleted();
          } catch (e) {
            print('[PlaybackManager] Error in _onSongCompleted: $e');
          }
        }());
      }
    });

    // Listen to skip next button from notification
    _skipNextSubscription = audioHandler?.onSkipNext.listen((_) {
      print('[PlaybackManager] Skip Next pressed from notification');
      skipNext();
    });

    // Listen to skip previous button from notification
    _skipPreviousSubscription = audioHandler?.onSkipPrevious.listen((_) {
      print('[PlaybackManager] Skip Previous pressed from notification');
      skipPrevious();
    });

    // Set up periodic save timer for position updates
    _saveTimer = Timer.periodic(_saveDebounceDuration, (_) async {
      if (currentSong != null && isPlaying) {
        await _saveState();
      }
    });

    // Restore saved state
    _restoreState();
  }

  void _onCastStateChanged() {
    final status = _castService.mediaStatus;
    final nextState = status?.playerState;
    final idleReason = status?.idleReason;

    final wasAdvancing =
        _lastObservedCastPlayerState == CastMediaPlayerState.playing ||
            _lastObservedCastPlayerState == CastMediaPlayerState.buffering ||
            _lastObservedCastPlayerState == CastMediaPlayerState.loading;
    final completedRemotely = wasAdvancing &&
        nextState == CastMediaPlayerState.idle &&
        idleReason == GoogleCastMediaIdleReason.finished;

    _lastObservedCastPlayerState = nextState;

    if (!_castService.isConnected) {
      _lastObservedCastPlayerState = null;
      notifyListeners();
      return;
    }

    if (completedRemotely && !_isHandlingCastCompletion) {
      _isHandlingCastCompletion = true;
      unawaited(() async {
        try {
          await _onSongCompleted();
        } catch (e) {
          print('[PlaybackManager] Error in remote _onSongCompleted: $e');
        } finally {
          _isHandlingCastCompletion = false;
        }
      }());
    }

    notifyListeners();
  }

  /// Play a single song immediately (clears queue and starts fresh)
  Future<void> playSong(Song song) async {
    print('[PlaybackManager] ========== playSong() called ==========');
    print('[PlaybackManager] Song: ${song.title} by ${song.artist}');
    print('[PlaybackManager] FilePath: ${song.filePath}');
    print('[PlaybackManager] Duration: ${song.duration}');

    // Clear restored position - this is a NEW song, start from beginning
    _invalidatePendingRestore('playSong');
    _restoredPosition = null;
    _pendingUiPosition = null;

    // Reset shuffle state - new queue means fresh shuffle context
    _isShuffleEnabled = false;
    _shuffleService.reset();

    try {
      // Create new queue with just this song
      print('[PlaybackManager] Creating new queue...');
      _queue = PlaybackQueue();
      _queue.addSong(song);
      print('[PlaybackManager] Queue created with ${_queue.length} song(s)');
      print(
          '[PlaybackManager] Current song in queue: ${_queue.currentSong?.title}');

      print('[PlaybackManager] Calling _playCurrentSong()...');
      await _playCurrentSong();
      print(
          '[PlaybackManager] _playCurrentSong() completed, notifying listeners...');
      notifyListeners();
      await _saveState(); // Save state after playing new song
      print('[PlaybackManager] ========== playSong() completed ==========');
    } catch (e, stackTrace) {
      print('[PlaybackManager] ========== ERROR in playSong() ==========');
      print('[PlaybackManager] Error: $e');
      print('[PlaybackManager] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Play a list of songs starting at a specific index
  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) async {
    try {
      if (songs.isEmpty) return;

      // Clear restored position - these are NEW songs, start from beginning
      _invalidatePendingRestore('playSongs');
      _restoredPosition = null;
      _pendingUiPosition = null;

      // Reset shuffle state - new queue means fresh shuffle context
      _isShuffleEnabled = false;
      _shuffleService.reset();

      // Create new queue with all songs
      _queue = PlaybackQueue();
      for (final song in songs) {
        _queue.addSong(song);
      }

      // Jump to start index
      if (startIndex > 0 && startIndex < songs.length) {
        _queue.jumpToIndex(startIndex);
      }

      await _playCurrentSong();
      notifyListeners();
      await _saveState(); // Save state after playing songs
    } catch (e) {
      print('[PlaybackManager] Error playing songs: $e');
      rethrow;
    }
  }

  /// Play all songs and shuffle if requested
  Future<void> playShuffled(List<Song> songs) async {
    try {
      if (songs.isEmpty) return;

      // Clear restored position - these are NEW songs, start from beginning
      _invalidatePendingRestore('playShuffled');
      _restoredPosition = null;
      _pendingUiPosition = null;

      // Shuffle the list using shuffle service
      final shuffled = _shuffleService.enableShuffle(songs, null);

      // Create queue with shuffled songs
      _queue = PlaybackQueue();
      for (final song in shuffled) {
        _queue.addSong(song);
      }

      _isShuffleEnabled = true;
      await _playCurrentSong();
      notifyListeners();
      await _saveState(); // Save state after playing shuffled
    } catch (e) {
      print('[PlaybackManager] Error playing shuffled: $e');
      rethrow;
    }
  }

  /// Add song to end of queue
  void addToQueue(Song song) {
    _queue.addSong(song);
    notifyListeners();
  }

  /// Add multiple songs to queue
  void addAllToQueue(List<Song> songs) {
    for (final song in songs) {
      _queue.addSong(song);
    }
    notifyListeners();
  }

  /// Insert song to play next
  void playNext(Song song) {
    _queue.insertSong(_queue.currentIndex + 1, song);
    notifyListeners();
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    try {
      if (_castService.isConnected) {
        if (isPlaying) {
          await _statsService.onSongStopped();
          await _castService.pause();
        } else {
          if (currentSong == null) return;
          _statsService.onSongStarted(currentSong!);
          await _castService.play();
        }
        notifyListeners();
        return;
      }

      if (isPlaying) {
        // Pausing - stop stats tracking
        await _statsService.onSongStopped();
        await _audioPlayer.pause();
        await _saveState(); // Save state when pausing
      } else {
        if (currentSong == null) return;

        // If no song is loaded yet OR we have a restored position to seek to, load/reload the song
        if (duration == null || _restoredPosition != null) {
          await _playCurrentSong();
        } else {
          // Resuming - restart stats tracking
          _statsService.onSongStarted(currentSong!);
          await _audioPlayer.resume();
        }
      }
      notifyListeners();
    } catch (e) {
      print('[PlaybackManager] Error in togglePlayPause: $e');
    }
  }

  /// Skip to next song
  Future<void> skipNext() async {
    try {
      if (!_queue.hasNext) {
        // Check repeat mode
        if (_repeatMode == RepeatMode.all && _queue.songs.isNotEmpty) {
          // Find first available song from beginning when wrapping
          final nextIndex = await _findNextAvailableSongIndexFrom(0);
          if (nextIndex != null) {
            await _statsService.onSongStopped();
            _queue.jumpToIndex(nextIndex);
            _restoredPosition = null;
            _pendingUiPosition = null;
            await _playCurrentSong();
            notifyListeners();
            await _saveState();
          }
        } else if (_repeatMode == RepeatMode.one) {
          // Replay current song
          await seek(Duration.zero);
          _statsService.onSongStarted(currentSong!);
          if (_castService.isConnected) {
            await _castService.play();
          } else {
            await _audioPlayer.resume();
          }
        }
        return;
      }

      // Find next available song
      final nextIndex = await _findNextAvailableSongIndex();
      if (nextIndex == null) {
        print('[PlaybackManager] No available next song found');
        return;
      }

      // Stop tracking current song
      await _statsService.onSongStopped();

      _queue.jumpToIndex(nextIndex);
      // Clear restored position so new song starts from beginning
      _restoredPosition = null;
      _pendingUiPosition = null;
      await _playCurrentSong();
      notifyListeners();
      await _saveState(); // Save state after skipping to next song
    } catch (e) {
      print('[PlaybackManager] Error skipping next: $e');
    }
  }

  /// Skip to previous song
  Future<void> skipPrevious() async {
    try {
      // If more than 3 seconds into song, restart it
      if (position.inSeconds > 3) {
        await seek(Duration.zero);
        return;
      }

      if (!_queue.hasPrevious) return;

      // Find previous available song when offline
      final previousIndex = await _findPreviousAvailableSongIndex();
      if (previousIndex == null) {
        print('[PlaybackManager] No available previous song found');
        return;
      }

      // Stop tracking current song
      await _statsService.onSongStopped();

      _queue.jumpToIndex(previousIndex);
      // Clear restored position so new song starts from beginning
      _restoredPosition = null;
      _pendingUiPosition = null;
      await _playCurrentSong();
      notifyListeners();
      await _saveState(); // Save state after skipping to previous song
    } catch (e) {
      print('[PlaybackManager] Error skipping previous: $e');
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    try {
      if (_castService.isConnected) {
        await _castService.seek(position, playAfterSeek: isPlaying);
        notifyListeners();
        return;
      }

      await _audioPlayer.seek(position);
      notifyListeners();
    } catch (e) {
      print('[PlaybackManager] Error seeking: $e');
    }
  }

  Future<void> startCastingToDevice(GoogleCastDevice device) async {
    if (_isCastTransitionInProgress) {
      print('[PlaybackManager] Cast handoff already in progress');
      return;
    }
    if (_castService.isConnected || _castService.isConnecting) {
      print('[PlaybackManager] Cast handoff ignored: session already active');
      return;
    }

    _isCastTransitionInProgress = true;
    notifyListeners();

    var snapshot = _PlaybackHandoffState(
      song: currentSong,
      position: _pendingUiPosition ?? _audioPlayer.position,
      wasPlaying: _audioPlayer.isPlaying,
    );
    final initialSongId = snapshot.song?.id;
    final shouldFreezeLocal = snapshot.wasPlaying || _audioPlayer.isLoading;

    try {
      if (shouldFreezeLocal) {
        await _audioPlayer.pause();
        await Future.delayed(const Duration(milliseconds: 120));

        final frozenSong = currentSong;
        if (initialSongId != null && frozenSong?.id != initialSongId) {
          throw StateError(
            'Playback changed during Chromecast handoff; aborting cast.',
          );
        }

        final frozenPosition = _pendingUiPosition ?? _audioPlayer.position;
        snapshot = _PlaybackHandoffState(
          song: frozenSong ?? snapshot.song,
          position: frozenPosition > snapshot.position
              ? frozenPosition
              : snapshot.position,
          wasPlaying: snapshot.wasPlaying,
        );
        _pendingUiPosition = snapshot.position;
        print(
          '[PlaybackManager] Frozen local playback for cast: '
          'song=${snapshot.song?.id}/${snapshot.song?.title} '
          'position=${snapshot.position.inMilliseconds}ms '
          'wasPlaying=${snapshot.wasPlaying}',
        );
        notifyListeners();
      }

      await _castService.connectToDevice(device);

      if (snapshot.song != null) {
        if (currentSong?.id != snapshot.song?.id) {
          throw StateError(
            'Queue song changed during Chromecast handoff; aborting cast.',
          );
        }
        final casted = await _castService.syncFromPlayback(
          song: snapshot.song,
          position: snapshot.position,
          isPlaying: snapshot.wasPlaying,
          force: true,
        );
        if (!casted) {
          throw StateError(
            'Chromecast session connected but the media handoff failed.',
          );
        }
      }

      notifyListeners();
    } catch (e) {
      await _restoreLocalPlaybackSnapshot(snapshot);
      rethrow;
    } finally {
      _isCastTransitionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> stopCastingAndResumeLocal() async {
    if (!_castService.isConnected) {
      return;
    }

    _castService.logDebugSnapshot('playback-manager-pre-disconnect');
    final snapshot = _PlaybackHandoffState(
      song: currentSong,
      position: _castService.remotePosition,
      wasPlaying: _castService.isRemotePlaying,
    );
    print(
      '[PlaybackManager] Disconnect snapshot: '
      'song=${snapshot.song?.id}/${snapshot.song?.title} '
      'rawRemote=${_castService.rawRemotePosition.inMilliseconds}ms '
      'capturedRemote=${snapshot.position.inMilliseconds}ms '
      'wasPlaying=${snapshot.wasPlaying}',
    );

    if (snapshot.song == null) {
      await _castService.beginLocalPlaybackHandoff(
        capturedPosition: snapshot.position,
        wasPlaying: snapshot.wasPlaying,
      );
      _castService.disconnectInBackground();
      notifyListeners();
      return;
    }

    await _castService.beginLocalPlaybackHandoff(
      capturedPosition: snapshot.position,
      wasPlaying: snapshot.wasPlaying,
    );
    print(
      '[PlaybackManager] Local handoff prepared, continuing with local restore',
    );
    await _restoreLocalPlaybackSnapshot(snapshot);
    _castService.disconnectInBackground();
    print('[PlaybackManager] Background Chromecast disconnect requested');
    await _saveState();
  }

  /// Toggle shuffle mode
  void toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_isShuffleEnabled && _queue.isNotEmpty) {
      // Shuffle remaining songs in queue (keeping current song at position 0)
      final shuffled =
          _shuffleService.enableShuffle(_queue.songs, _queue.currentSong);

      // Rebuild queue with shuffled songs, current song is at index 0
      _queue.setQueue(shuffled, currentIndex: 0);
    } else if (!_isShuffleEnabled && _shuffleService.isShuffled) {
      // Restore original order
      final original = _shuffleService.disableShuffle(_queue.currentSong);

      // Find where the current song is in the original queue
      final currentSong = _queue.currentSong;
      int newIndex = 0;
      if (currentSong != null) {
        final foundIndex = original.indexOf(currentSong);
        if (foundIndex != -1) {
          newIndex = foundIndex;
        }
      }

      // Rebuild queue with original order, maintaining current song position
      _queue.setQueue(original, currentIndex: newIndex);
    }

    notifyListeners();
    await _saveState(); // Save state after shuffle toggle
  }

  /// Reorder queue after a drag in the queue screen's "current first" display order.
  /// Indices match [ReorderableListView] after the usual `newIndex -= 1` adjustment when moving down.
  /// The playing track stays pinned at display index 0.
  void reorderQueueFromDisplayOrder(int oldDisplayIndex, int newDisplayIndex) {
    final songs = _queue.songs;
    if (songs.isEmpty) return;

    final len = songs.length;
    final c = _queue.currentIndex.clamp(0, len - 1);
    final displayed = <Song>[
      ...songs.sublist(c),
      ...songs.sublist(0, c),
    ];

    if (oldDisplayIndex < 0 ||
        oldDisplayIndex >= len ||
        newDisplayIndex < 0 ||
        newDisplayIndex >= len) {
      return;
    }

    // Now playing is pinned at the top; drag handle is disabled for row 0.
    if (oldDisplayIndex == 0) return;
    if (newDisplayIndex == 0 && oldDisplayIndex != 0) return;

    final moved = displayed.removeAt(oldDisplayIndex);
    displayed.insert(newDisplayIndex, moved);

    final current = _queue.currentSong;
    if (current != null && displayed.first.id != current.id) {
      return;
    }

    _queue.setQueue(displayed, currentIndex: 0);
    notifyListeners();
    unawaited(_saveState());
  }

  /// Toggle repeat mode (cycles through none → all → one)
  void toggleRepeat() async {
    _repeatMode = _repeatMode.next;
    notifyListeners();
    await _saveState(); // Save state after repeat toggle
  }

  /// Clear the queue and stop playback
  Future<void> clearQueue() async {
    // Stop tracking current song
    await _statsService.onSongStopped();
    await _audioPlayer.stop();
    _queue.clear();
    await _stateManager.clearCompletePlaybackState(); // Clear saved state
    notifyListeners();
  }

  /// Internal: Play the current song in the queue
  Future<void> _playCurrentSong({
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
          notifyListeners();
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
            notifyListeners();
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
        notifyListeners();

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

  Future<void> _restoreLocalPlaybackSnapshot(
    _PlaybackHandoffState snapshot,
  ) async {
    if (snapshot.song == null) {
      return;
    }

    final loadedLocalSong = _audioPlayer.currentSong;
    final loadedSongMatches = loadedLocalSong?.id == snapshot.song?.id;

    print(
      '[PlaybackManager] Restoring local snapshot: '
      'song=${snapshot.song?.id}/${snapshot.song?.title} '
      'loadedLocalSong=${loadedLocalSong?.id}/${loadedLocalSong?.title} '
      'loadedSongMatches=$loadedSongMatches '
      'target=${snapshot.position.inMilliseconds}ms '
      'wasPlaying=${snapshot.wasPlaying} '
      'localBefore=${_audioPlayer.position.inMilliseconds}ms',
    );
    _pendingUiPosition = snapshot.position;

    if (!loadedSongMatches) {
      print(
        '[PlaybackManager] Loaded local song mismatch during restore, '
        'reloading snapshot song instead of resuming in-place',
      );
      await _reloadLocalPlaybackFromSnapshot(snapshot);
      notifyListeners();
      return;
    }

    try {
      await _audioPlayer.seek(snapshot.position);
      print(
        '[PlaybackManager] Local seek completed: '
        'afterSeek=${_audioPlayer.position.inMilliseconds}ms',
      );
      if (snapshot.wasPlaying) {
        await _audioPlayer.resume();
        print(
          '[PlaybackManager] Local resume requested: '
          'afterResume=${_audioPlayer.position.inMilliseconds}ms '
          'isPlaying=${_audioPlayer.isPlaying}',
        );
        final resumeRecovered =
            await _verifyLocalResumeProgress(snapshot.position);
        if (!resumeRecovered) {
          print(
            '[PlaybackManager] Local resume stalled, reloading current song at '
            '${snapshot.position.inMilliseconds}ms',
          );
          await _reloadLocalPlaybackFromSnapshot(snapshot);
        }
      }
    } catch (_) {
      _restoredPosition = snapshot.position;
      print(
        '[PlaybackManager] Local restore fallback triggered: '
        'restoredPosition=${_restoredPosition?.inMilliseconds}ms',
      );
      await _playCurrentSong(
        autoPlay: snapshot.wasPlaying,
        restartStatsTracking: false,
      );
      print(
        '[PlaybackManager] Local restore fallback completed: '
        'localAfterFallback=${_audioPlayer.position.inMilliseconds}ms '
        'isPlaying=${_audioPlayer.isPlaying}',
      );
    }

    notifyListeners();
  }

  Future<bool> _verifyLocalResumeProgress(Duration expectedPosition) async {
    await Future.delayed(const Duration(milliseconds: 900));

    final currentPosition = _audioPlayer.position;
    final minimumAdvancedPosition =
        expectedPosition + const Duration(milliseconds: 250);
    final hasAdvanced = currentPosition >= minimumAdvancedPosition;

    print(
      '[PlaybackManager] Local resume verification: '
      'current=${currentPosition.inMilliseconds}ms '
      'expectedAtLeast=${minimumAdvancedPosition.inMilliseconds}ms '
      'isPlaying=${_audioPlayer.isPlaying} '
      'hasAdvanced=$hasAdvanced',
    );

    return hasAdvanced;
  }

  Future<void> _reloadLocalPlaybackFromSnapshot(
    _PlaybackHandoffState snapshot,
  ) async {
    _restoredPosition = snapshot.position;
    _pendingUiPosition = snapshot.position;
    await _playCurrentSong(
      autoPlay: snapshot.wasPlaying,
      restartStatsTracking: false,
    );
    print(
      '[PlaybackManager] Local reload after stalled resume completed: '
      'localAfterReload=${_audioPlayer.position.inMilliseconds}ms '
      'isPlaying=${_audioPlayer.isPlaying}',
    );
  }

  /// Internal: Cache a song in the background for future offline playback
  void _cacheSongInBackground(Song song) async {
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

  /// Internal: Get stream URL with retry-once logic for expired stream tokens
  ///
  /// For authenticated streaming, if the stream ticket request fails with
  /// STREAM_TOKEN_EXPIRED, this method will retry once with a fresh token.
  Future<String> _getStreamUrlWithRetry(
      Song song, StreamingQuality quality) async {
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

  String? _extractStreamToken(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return uri.queryParameters['streamToken'];
  }

  /// Internal: Find the next available song in the queue (starting from current index + 1)
  /// Returns the index of the next available song, or null if none found
  Future<int?> _findNextAvailableSongIndex() async {
    final songs = _queue.songs;
    final currentIndex = _queue.currentIndex;

    // If online, just return the next index
    if (!_offlineService.isOffline) {
      return currentIndex < songs.length - 1 ? currentIndex + 1 : null;
    }

    // Search forward from current position
    for (int i = currentIndex + 1; i < songs.length; i++) {
      final isAvailable =
          await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    // If repeat all is enabled, wrap around and search from beginning
    if (_repeatMode == RepeatMode.all) {
      for (int i = 0; i < currentIndex; i++) {
        final isAvailable =
            await _offlineService.isSongAvailableOffline(songs[i].id);
        if (isAvailable) {
          return i;
        }
      }
    }

    return null; // No available songs found
  }

  /// Internal: Find the next available song starting from a specific index
  /// Used when wrapping around in repeat-all mode
  Future<int?> _findNextAvailableSongIndexFrom(int startIndex) async {
    final songs = _queue.songs;

    // If online, just return the start index
    if (!_offlineService.isOffline) {
      return startIndex < songs.length ? startIndex : null;
    }

    // Search from start index
    for (int i = startIndex; i < songs.length; i++) {
      final isAvailable =
          await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    return null;
  }

  /// Internal: Find the previous available song in the queue (starting from current index - 1)
  /// Returns the index of the previous available song, or null if none found
  Future<int?> _findPreviousAvailableSongIndex() async {
    final songs = _queue.songs;
    final currentIndex = _queue.currentIndex;

    // If online, just return the previous index
    if (!_offlineService.isOffline) {
      return currentIndex > 0 ? currentIndex - 1 : null;
    }

    // Search backward from current position
    for (int i = currentIndex - 1; i >= 0; i--) {
      final isAvailable =
          await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    // If repeat all is enabled, wrap around and search from end
    if (_repeatMode == RepeatMode.all) {
      for (int i = songs.length - 1; i > currentIndex; i--) {
        final isAvailable =
            await _offlineService.isSongAvailableOffline(songs[i].id);
        if (isAvailable) {
          return i;
        }
      }
    }

    return null; // No available songs found
  }

  /// Internal: Handle song completion
  Future<void> _onSongCompleted() async {
    print('[PlaybackManager] Song completed');

    if (_repeatMode == RepeatMode.one) {
      // Replay the same song - finalize current first
      await _statsService.onSongStopped();
      await _playCurrentSong();
    } else if (_queue.hasNext) {
      // Move to next song - skipNext() will handle finalization
      // Don't call onSongStopped() here to avoid double-call
      await skipNext();
    } else if (_repeatMode == RepeatMode.all && _queue.songs.isNotEmpty) {
      // Restart from beginning - finalize current first
      await _statsService.onSongStopped();
      _queue.jumpToIndex(0);
      await _playCurrentSong();
    } else {
      // Queue finished, stop - finalize current first
      await _statsService.onSongStopped();
      _audioPlayer.stop();
      notifyListeners();
    }
  }

  /// Save current playback state to device storage
  Future<void> _saveState() async {
    // Skip if queue is empty
    if (_queue.isEmpty) return;

    // Get original queue if shuffled
    List<Song>? originalQueue;
    if (_isShuffleEnabled && _shuffleService.originalQueue.isNotEmpty) {
      originalQueue = _shuffleService.originalQueue.cast<Song>();
    }

    // Save state to persistent storage
    await _stateManager.saveCompletePlaybackState(
      queue: _queue,
      isShuffleEnabled: _isShuffleEnabled,
      repeatMode: _repeatMode,
      position: position,
      originalQueue: originalQueue,
    );
  }

  /// Public helper for callers that need to guarantee the state is flushed
  Future<void> saveStateImmediately() async {
    await _saveState();
  }

  /// Restore saved playback state from device storage
  Future<void> _restoreState() async {
    final restoreGeneration = _restoreGeneration;
    try {
      final savedState = await _stateManager.loadCompletePlaybackState();
      if (savedState == null) return;

      final restoredSongs = await _rehydrateSongs(savedState.queue.songs);
      final restoredQueue = PlaybackQueue(
        songs: restoredSongs,
        currentIndex: savedState.queue.currentIndex,
      );

      // Restore queue
      if (restoreGeneration != _restoreGeneration) {
        print(
          '[PlaybackManager] Skipping stale restore before queue apply: '
          'restoreGeneration=$restoreGeneration currentGeneration=$_restoreGeneration',
        );
        return;
      }
      _queue = restoredQueue;

      // Restore shuffle state and original queue
      _isShuffleEnabled = savedState.isShuffleEnabled;
      if (_isShuffleEnabled && savedState.originalQueue != null) {
        final restoredOriginalQueue =
            await _rehydrateSongs(savedState.originalQueue!);
        // Manually restore shuffle service state
        _shuffleService.enableShuffle(
          restoredOriginalQueue,
          _queue.currentSong,
        );
      }

      // Restore repeat mode
      _repeatMode = savedState.repeatMode;

      // Store playback position to seek to when user presses play
      if (_queue.currentSong != null && savedState.position > Duration.zero) {
        if (restoreGeneration != _restoreGeneration) {
          print(
            '[PlaybackManager] Skipping stale restore before position apply: '
            'restoreGeneration=$restoreGeneration currentGeneration=$_restoreGeneration',
          );
          return;
        }
        _restoredPosition = savedState.position;
        _pendingUiPosition = savedState.position;
      }

      notifyListeners();
    } catch (e) {
      print('[PlaybackManager] Error restoring state: $e');
    }
  }

  @override
  void dispose() {
    _isInitialized = false;
    _castService.removeListener(_onCastStateChanged);
    _saveTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPreviousSubscription?.cancel();
    super.dispose();
  }

  void _invalidatePendingRestore(String reason) {
    _restoreGeneration++;
    print(
      '[PlaybackManager] Invalidated pending restore: '
      'reason=$reason generation=$_restoreGeneration',
    );
  }

  Future<List<Song>> _rehydrateSongs(List<Song> songs) async {
    if (songs.isEmpty) return songs;

    final librarySongsById = <String, SongModel>{};
    final downloadedSongsById = <String, Song>{};

    try {
      final librarySongs = await _libraryRepository.getSongs();
      for (final song in librarySongs) {
        librarySongsById[song.id] = song;
      }
    } catch (e) {
      print('[PlaybackManager] Failed to load library songs for restore: $e');
    }

    try {
      await _downloadManager.initialize();
      for (final task in _downloadManager.queue) {
        if (task.status != DownloadStatus.completed) continue;
        downloadedSongsById[task.songId] = Song(
          id: task.songId,
          title: task.title,
          artist: task.artist,
          album: task.albumName,
          albumId: task.albumId,
          albumArtist: task.albumArtist,
          trackNumber: task.trackNumber,
          duration: Duration(seconds: task.duration),
          filePath: task.songId,
          fileSize: task.bytesDownloaded,
          modifiedTime: DateTime.now(),
        );
      }
    } catch (e) {
      print(
          '[PlaybackManager] Failed to load downloaded songs for restore: $e');
    }

    return songs
        .map(
          (song) => _rehydrateSong(
            song,
            librarySong: librarySongsById[song.id],
            downloadedSong: downloadedSongsById[song.id],
          ),
        )
        .toList();
  }

  Song _rehydrateSong(
    Song song, {
    SongModel? librarySong,
    Song? downloadedSong,
  }) {
    var repaired = song;

    if (downloadedSong != null) {
      repaired = repaired.copyWith(
        title: downloadedSong.title,
        artist: downloadedSong.artist,
        album: downloadedSong.album ?? repaired.album,
        albumId: downloadedSong.albumId ?? repaired.albumId,
        albumArtist: downloadedSong.albumArtist ?? repaired.albumArtist,
        trackNumber: downloadedSong.trackNumber ?? repaired.trackNumber,
        duration: downloadedSong.duration > Duration.zero
            ? downloadedSong.duration
            : repaired.duration,
      );
    }

    if (librarySong != null) {
      repaired = repaired.copyWith(
        title: librarySong.title,
        artist: librarySong.artist,
        albumId: librarySong.albumId ?? repaired.albumId,
        trackNumber: librarySong.trackNumber ?? repaired.trackNumber,
        duration: librarySong.duration > 0
            ? Duration(seconds: librarySong.duration)
            : repaired.duration,
      );
    }

    return repaired;
  }

  void _updateCurrentSongDuration(Duration duration) {
    final currentSong = _queue.currentSong;
    if (currentSong == null || currentSong.duration == duration) {
      return;
    }

    final updatedSongs = List<Song>.from(_queue.songs);
    updatedSongs[_queue.currentIndex] =
        currentSong.copyWith(duration: duration);
    _queue = PlaybackQueue(
      songs: updatedSongs,
      currentIndex: _queue.currentIndex,
    );
    unawaited(_saveState());
  }
}

class _PlaybackHandoffState {
  final Song? song;
  final Duration position;
  final bool wasPlaying;

  const _PlaybackHandoffState({
    required this.song,
    required this.position,
    required this.wasPlaying,
  });
}
