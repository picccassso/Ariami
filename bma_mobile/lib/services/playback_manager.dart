import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/playback_queue.dart';
import '../models/repeat_mode.dart';
import 'audio/audio_player_service.dart';
import 'audio/shuffle_service.dart';
import 'api/connection_service.dart';

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

  // State
  PlaybackQueue _queue = PlaybackQueue();
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.none;

  // Stream subscriptions
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription? _playerStateSubscription;

  // Getters
  Song? get currentSong => _queue.currentSong;
  bool get isPlaying => _audioPlayer.isPlaying;
  bool get isLoading => _audioPlayer.isLoading;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  PlaybackQueue get queue => _queue;
  bool get hasNext => _queue.hasNext;
  bool get hasPrevious => _queue.hasPrevious;

  /// Initialize the playback manager and set up listeners
  void initialize() {
    // Listen to position updates
    _positionSubscription = _audioPlayer.positionStream.listen((_) {
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
        await _audioPlayer.pause();
      } else {
        if (currentSong == null) {
          // No song loaded, can't play
          return;
        }
        await _audioPlayer.resume();
      }
      notifyListeners();
    } catch (e) {
      print('[PlaybackManager] Error toggling play/pause: $e');
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
  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_isShuffleEnabled && _queue.isNotEmpty) {
      // Shuffle remaining songs in queue (keeping current song at position 0)
      final shuffled = _shuffleService.enableShuffle(_queue.songs, _queue.currentSong);

      // Rebuild queue with shuffled songs
      _queue = PlaybackQueue();
      for (final song in shuffled) {
        _queue.addSong(song);
      }
    } else if (!_isShuffleEnabled && _shuffleService.isShuffled) {
      // Restore original order
      final original = _shuffleService.disableShuffle(_queue.currentSong);
      _queue = PlaybackQueue();
      for (final song in original) {
        _queue.addSong(song);
      }
    }

    notifyListeners();
  }

  /// Toggle repeat mode (cycles through none → all → one)
  void toggleRepeat() {
    _repeatMode = _repeatMode.next;
    notifyListeners();
  }

  /// Clear the queue and stop playback
  Future<void> clearQueue() async {
    await _audioPlayer.stop();
    _queue.clear();
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
      print('[PlaybackManager] Calling AudioPlayerService.play()...');

      await _audioPlayer.play(streamUrl);

      print('[PlaybackManager] AudioPlayerService.play() returned successfully!');
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

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    super.dispose();
  }
}
