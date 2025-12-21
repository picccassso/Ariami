import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/playback_queue.dart';
import '../models/repeat_mode.dart';
import 'audio/audio_player_service.dart';
import 'audio/shuffle_service.dart';
import 'audio/playback_state_manager.dart';
import 'api/connection_service.dart';
import 'offline/offline_playback_service.dart';
import 'cache/cache_manager.dart';
import 'stats/streaming_stats_service.dart';
import '../main.dart' show audioHandler;

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
  final StreamingStatsService _statsService = StreamingStatsService();

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
  Duration? _pendingUiPosition; // Temporary UI override for restored seek position

  // Getters
  Song? get currentSong => _queue.currentSong;
  bool get isPlaying => _audioPlayer.isPlaying;
  bool get isLoading => _audioPlayer.isLoading;
  Duration get position => _pendingUiPosition ?? _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration ?? _queue.currentSong?.duration;
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  PlaybackQueue get queue => _queue;
  bool get hasNext => _queue.hasNext;
  bool get hasPrevious => _queue.hasPrevious;

  /// Initialize the playback manager and set up listeners
  void initialize() {
    // Listen to position updates
    _positionSubscription = _audioPlayer.positionStream.listen((pos) {
      if (_pendingUiPosition != null && pos >= _pendingUiPosition!) {
        _pendingUiPosition = null;
      }
      notifyListeners();
    });

    // Listen to duration updates
    _durationSubscription = _audioPlayer.durationStream.listen((_) {
      notifyListeners();
    });

    // Listen to player state changes
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      notifyListeners();

      // Auto-advance when song completes
      if (state.processingState.toString() == 'ProcessingState.completed') {
        _onSongCompleted().catchError((e) {
          print('[PlaybackManager] Error in _onSongCompleted: $e');
        });
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

  /// Play a single song immediately (clears queue and starts fresh)
  Future<void> playSong(Song song) async {
    print('[PlaybackManager] ========== playSong() called ==========');
    print('[PlaybackManager] Song: ${song.title} by ${song.artist}');
    print('[PlaybackManager] FilePath: ${song.filePath}');
    print('[PlaybackManager] Duration: ${song.duration}');

    // Clear restored position - this is a NEW song, start from beginning
    _restoredPosition = null;
    _pendingUiPosition = null;

    try {
      // Create new queue with just this song
      print('[PlaybackManager] Creating new queue...');
      _queue = PlaybackQueue();
      _queue.addSong(song);
      print('[PlaybackManager] Queue created with ${_queue.length} song(s)');
      print('[PlaybackManager] Current song in queue: ${_queue.currentSong?.title}');

      print('[PlaybackManager] Calling _playCurrentSong()...');
      await _playCurrentSong();
      print('[PlaybackManager] _playCurrentSong() completed, notifying listeners...');
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
      _restoredPosition = null;
      _pendingUiPosition = null;

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
          await _audioPlayer.resume();
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
      await _audioPlayer.seek(position);
      notifyListeners();
    } catch (e) {
      print('[PlaybackManager] Error seeking: $e');
    }
  }

  /// Toggle shuffle mode
  void toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_isShuffleEnabled && _queue.isNotEmpty) {
      // Shuffle remaining songs in queue (keeping current song at position 0)
      final shuffled = _shuffleService.enableShuffle(_queue.songs, _queue.currentSong);

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
  Future<void> _playCurrentSong() async {
    print('[PlaybackManager] _playCurrentSong() called');

    final song = _queue.currentSong;
    if (song == null) {
      print('[PlaybackManager] ERROR: No current song in queue!');
      return;
    }

    print('[PlaybackManager] Current song: ${song.title}');

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
          audioUrl = 'file://$localPath';
          print('[PlaybackManager] Playing from downloaded file: $audioUrl');
          
          // Get cached artwork for offline playback
          if (song.albumId != null) {
            final cachedArtworkPath = await _cacheManager.getArtworkPath(song.albumId!);
            if (cachedArtworkPath != null) {
              artworkUri = Uri.file(cachedArtworkPath);
              print('[PlaybackManager] Using cached artwork: $artworkUri');
            }
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
          
          // Get cached artwork for offline playback
          if (song.albumId != null) {
            final cachedArtworkPath = await _cacheManager.getArtworkPath(song.albumId!);
            if (cachedArtworkPath != null) {
              artworkUri = Uri.file(cachedArtworkPath);
              print('[PlaybackManager] Using cached artwork: $artworkUri');
            }
          }
          break;

        case PlaybackSource.stream:
          // Stream from server
          print('[PlaybackManager] Checking connection...');
          if (_connectionService.apiClient == null) {
            print('[PlaybackManager] ERROR: Not connected to server! apiClient is null');
            throw Exception('Not connected to server');
          }
          print('[PlaybackManager] Connected! Base URL: ${_connectionService.apiClient!.baseUrl}');
          audioUrl = '${_connectionService.apiClient!.baseUrl}/stream/${song.filePath}';
          print('[PlaybackManager] Streaming from server: $audioUrl');
          
          // Use server URL for artwork when streaming
          if (song.albumId != null) {
            artworkUri = Uri.parse('${_connectionService.apiClient!.baseUrl}/artwork/${song.albumId}');
            print('[PlaybackManager] Using server artwork: $artworkUri');
          }

          // Trigger background caching of the song for offline use
          _cacheSongInBackground(song);
          break;

        case PlaybackSource.unavailable:
          print('[PlaybackManager] Song not available offline, searching for next available song...');
          // Try to find and play the next available song
          final nextAvailableIndex = await _findNextAvailableSongIndex();
          if (nextAvailableIndex != null) {
            print('[PlaybackManager] Found available song at index $nextAvailableIndex, skipping to it');
            _queue.jumpToIndex(nextAvailableIndex);
            await _playCurrentSong(); // Recursive call to play the available song
          } else {
            // No songs available, stop playback
            print('[PlaybackManager] No available songs in queue, stopping playback');
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
        await _audioPlayer.resume();

        _restoredPosition = null; // Clear so it doesn't affect next song
      } else {
        // No restored position - play normally from the beginning
        await _audioPlayer.playSong(song, audioUrl, artworkUri: artworkUri);
      }

      // Track stats for this song playback
      print('[PlaybackManager] About to call onSongStarted for: ${song.title}');
      _statsService.onSongStarted(song);
      print('[PlaybackManager] onSongStarted called successfully');
    } catch (e, stackTrace) {
      print('[PlaybackManager] ERROR in _playCurrentSong: $e');
      print('[PlaybackManager] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Internal: Cache a song in the background for future offline playback
  void _cacheSongInBackground(Song song) {
    if (_connectionService.apiClient == null) return;

    // Construct the download URL for caching
    final downloadUrl = '${_connectionService.apiClient!.baseUrl}/download/${song.id}';

    // Trigger background cache (non-blocking)
    _cacheManager.cacheSong(song.id, downloadUrl).then((started) {
      if (started) {
        print('[PlaybackManager] Started background caching for: ${song.title}');
      }
    }).catchError((e) {
      print('[PlaybackManager] Failed to start background cache: $e');
    });
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
      final isAvailable = await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    // If repeat all is enabled, wrap around and search from beginning
    if (_repeatMode == RepeatMode.all) {
      for (int i = 0; i < currentIndex; i++) {
        final isAvailable = await _offlineService.isSongAvailableOffline(songs[i].id);
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
      final isAvailable = await _offlineService.isSongAvailableOffline(songs[i].id);
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
      final isAvailable = await _offlineService.isSongAvailableOffline(songs[i].id);
      if (isAvailable) {
        return i;
      }
    }

    // If repeat all is enabled, wrap around and search from end
    if (_repeatMode == RepeatMode.all) {
      for (int i = songs.length - 1; i > currentIndex; i--) {
        final isAvailable = await _offlineService.isSongAvailableOffline(songs[i].id);
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
    try {
      final savedState = await _stateManager.loadCompletePlaybackState();
      if (savedState == null) return;

      // Restore queue
      _queue = savedState.queue;

      // Restore shuffle state and original queue
      _isShuffleEnabled = savedState.isShuffleEnabled;
      if (_isShuffleEnabled && savedState.originalQueue != null) {
        // Manually restore shuffle service state
        _shuffleService.enableShuffle(
          savedState.originalQueue!,
          _queue.currentSong,
        );
      }

      // Restore repeat mode
      _repeatMode = savedState.repeatMode;

      // Store playback position to seek to when user presses play
      if (_queue.currentSong != null && savedState.position > Duration.zero) {
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
    _saveTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPreviousSubscription?.cancel();
    super.dispose();
  }
}
