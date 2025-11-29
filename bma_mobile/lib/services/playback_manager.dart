import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/playback_queue.dart';
import '../models/repeat_mode.dart';
import 'audio/audio_player_service.dart';
import 'audio/shuffle_service.dart';
import 'audio/playback_state_manager.dart';
import 'api/connection_service.dart';
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
        _onSongCompleted();
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
      print('🟡 [DEBUG] togglePlayPause() called');
      print('🟡 [DEBUG] isPlaying: $isPlaying');
      print('🟡 [DEBUG] currentSong: ${currentSong?.title}');
      print('🟡 [DEBUG] duration: $duration');
      print('🟡 [DEBUG] _restoredPosition: $_restoredPosition');

      if (isPlaying) {
        print('🟡 [DEBUG] Pausing...');
        await _audioPlayer.pause();
        await _saveState(); // Save state when pausing
      } else {
        if (currentSong == null) {
          print('🟡 [DEBUG] ❌ No current song, returning');
          return;
        }

        // If no song is loaded yet OR we have a restored position to seek to, load/reload the song
        if (duration == null || _restoredPosition != null) {
          print('🟡 [DEBUG] ✅ Duration is NULL or restored position exists - calling _playCurrentSong()...');
          await _playCurrentSong();
        } else {
          print('🟡 [DEBUG] ⚠️ Duration is NOT null and no restored position - calling resume()');
          print('🟡 [DEBUG] Duration value: $duration');
          await _audioPlayer.resume();
        }
      }
      notifyListeners();
    } catch (e) {
      print('🟡 [DEBUG] ❌ Error: $e');
    }
  }

  /// Skip to next song
  Future<void> skipNext() async {
    try {
      if (!_queue.hasNext) {
        // Check repeat mode
        if (_repeatMode == RepeatMode.all && _queue.songs.isNotEmpty) {
          // Restart from beginning
          _queue.jumpToIndex(0);
          await _playCurrentSong();
        } else if (_repeatMode == RepeatMode.one) {
          // Replay current song
          await seek(Duration.zero);
          await _audioPlayer.resume();
        }
        return;
      }

      _queue.moveToNext();
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

      _queue.moveToPrevious();
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
    print('[PlaybackManager] Checking connection...');

    if (_connectionService.apiClient == null) {
      print('[PlaybackManager] ERROR: Not connected to server! apiClient is null');
      throw Exception('Not connected to server');
    }

    print('[PlaybackManager] Connected! Base URL: ${_connectionService.apiClient!.baseUrl}');

    try {
      // Build stream URL for the song
      final streamUrl = '${_connectionService.apiClient!.baseUrl}/stream/${song.filePath}';
      print('[PlaybackManager] Stream URL: $streamUrl');

      print('🔴 [DEBUG] Checking _restoredPosition...');
      print('🔴 [DEBUG] _restoredPosition value: $_restoredPosition');

      // If we have a restored position, load without playing, seek, then play
      if (_restoredPosition != null) {
        print('🔴 [DEBUG] ✅ _restoredPosition is NOT null!');
        print('🔴 [DEBUG] Will load song, seek to ${_restoredPosition!.inSeconds}s, then play');

        // Load the song WITHOUT starting playback
        print('[PlaybackManager] Calling AudioPlayerService.loadSong() (no auto-play)...');
        await _audioPlayer.loadSong(song, streamUrl);

        // Wait for the audio player to be fully ready before seeking
        print('🔴 [DEBUG] Waiting 500ms for stream to be ready...');
        await Future.delayed(const Duration(milliseconds: 500));

        // Seek to the restored position BEFORE starting playback
        print('🔴 [DEBUG] Seeking to: ${_restoredPosition!.inSeconds}s (${_restoredPosition!.inMilliseconds}ms)');
        await _audioPlayer.seek(_restoredPosition!);

        print('🔴 [DEBUG] Position AFTER seek: ${_audioPlayer.position.inSeconds}s');

        // Notify listeners so UI updates with the new position
        notifyListeners();

        // NOW start playback from the seeked position
        print('🔴 [DEBUG] Starting playback from seeked position...');
        await _audioPlayer.resume();

        print('🔴 [DEBUG] ✅ Playback started! Clearing _restoredPosition...');
        _restoredPosition = null; // Clear so it doesn't affect next song
        print('🔴 [DEBUG] _restoredPosition cleared (now null)');
      } else {
        // No restored position - play normally from the beginning
        print('🔴 [DEBUG] ❌ _restoredPosition is NULL - playing normally from start');
        print('[PlaybackManager] Calling AudioPlayerService.playSong() with metadata...');

        await _audioPlayer.playSong(song, streamUrl);

        print('[PlaybackManager] AudioPlayerService.playSong() returned successfully!');
      }

      print('[PlaybackManager] Foreground service notification should now be visible');
      print('[PlaybackManager] isPlaying: ${_audioPlayer.isPlaying}');
      print('[PlaybackManager] isLoading: ${_audioPlayer.isLoading}');
    } catch (e, stackTrace) {
      print('[PlaybackManager] ERROR in _playCurrentSong: $e');
      print('[PlaybackManager] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Internal: Handle song completion
  void _onSongCompleted() {
    print('[PlaybackManager] Song completed');

    if (_repeatMode == RepeatMode.one) {
      // Replay the same song
      _playCurrentSong();
    } else if (_queue.hasNext) {
      // Move to next song
      skipNext();
    } else if (_repeatMode == RepeatMode.all && _queue.songs.isNotEmpty) {
      // Restart from beginning
      _queue.jumpToIndex(0);
      _playCurrentSong();
    } else {
      // Queue finished, stop
      _audioPlayer.stop();
      notifyListeners();
    }
  }

  /// Save current playback state to device storage
  Future<void> _saveState() async {
    // Skip if queue is empty
    if (_queue.isEmpty) {
      return;
    }

    print('🔵 [DEBUG] _saveState() called');
    print('🔵 [DEBUG] Current song: ${_queue.currentSong?.title}');
    print('🔵 [DEBUG] Current position: ${position.inSeconds}s (${position.inMilliseconds}ms)');
    print('🔵 [DEBUG] Queue size: ${_queue.length}');
    print('🔵 [DEBUG] Shuffle enabled: $_isShuffleEnabled');

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
      print('🟢 [DEBUG] _restoreState() called');

      final savedState = await _stateManager.loadCompletePlaybackState();

      if (savedState == null) {
        print('🟢 [DEBUG] No saved state found');
        return;
      }

      print('🟢 [DEBUG] Saved state loaded!');
      print('🟢 [DEBUG] Queue size: ${savedState.queue.length}');
      print('🟢 [DEBUG] Current song: ${savedState.queue.currentSong?.title}');
      print('🟢 [DEBUG] Saved position: ${savedState.position.inSeconds}s (${savedState.position.inMilliseconds}ms)');
      print('🟢 [DEBUG] Shuffle: ${savedState.isShuffleEnabled}');
      print('🟢 [DEBUG] Repeat: ${savedState.repeatMode}');

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
        print('🟢 [DEBUG] ✅ _restoredPosition SET to: ${_restoredPosition!.inSeconds}s');
        print('🟢 [DEBUG] Ready to resume: ${_queue.currentSong!.title}');
      } else {
        print('🟢 [DEBUG] ❌ _restoredPosition NOT set (position was zero or no song)');
      }

      notifyListeners();
    } catch (e) {
      print('🟢 [DEBUG] ❌ Error restoring state: $e');
    }
  }

  @override
  void dispose() {
    // Save state one final time before disposing
    _saveState();

    _saveTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPreviousSubscription?.cancel();
    super.dispose();
  }
}
