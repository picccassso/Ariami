import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:just_audio/just_audio.dart';
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

part 'playback_manager_queue_impl.dart';
part 'playback_manager_casting_impl.dart';
part 'playback_manager_streaming_impl.dart';
part 'playback_manager_persistence_impl.dart';

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
  Timer? _castStatsForwardTimer;

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
    _queue = PlaybackQueue();
    _isShuffleEnabled = false;
    _repeatMode = RepeatMode.none;
    _shuffleService.reset();
    _restoredPosition = null;
    _pendingUiPosition = null;

    _castService.initialize();
    _castService.addListener(_onCastStateChanged);

    // Listen to position updates
    _positionSubscription = _audioPlayer.positionStream.listen((pos) {
      if (_pendingUiPosition != null && pos >= _pendingUiPosition!) {
        _pendingUiPosition = null;
      }
      _statsService.updatePosition(pos);
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
      if (state.processingState == ProcessingState.completed) {
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
      _castStatsForwardTimer?.cancel();
      _castStatsForwardTimer = null;
      notifyListeners();
      return;
    }

    // Forward cast position updates to stats service
    _castStatsForwardTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_castService.isConnected) {
          _statsService.updatePosition(_castService.remotePosition);
        }
      },
    );

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
  Future<void> playSong(Song song) => _playSongImpl(song);

  /// Play a list of songs starting at a specific index
  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) =>
      _playSongsImpl(songs, startIndex: startIndex);

  /// Play all songs and shuffle if requested
  Future<void> playShuffled(List<Song> songs) => _playShuffledImpl(songs);

  /// Add song to end of queue
  void addToQueue(Song song) => _addToQueueImpl(song);

  /// Add multiple songs to queue
  void addAllToQueue(List<Song> songs) => _addAllToQueueImpl(songs);

  /// Insert song to play next
  void playNext(Song song) => _playNextImpl(song);

  /// Toggle play/pause
  Future<void> togglePlayPause() => _togglePlayPauseImpl();

  /// Skip to next song
  Future<void> skipNext() => _skipNextImpl(completedNaturally: false);

  /// Skip to previous song
  Future<void> skipPrevious() => _skipPreviousImpl();

  /// Skip to a specific queue item
  Future<void> skipToQueueItem(int index) => _skipToQueueItemImpl(index);

  /// Seek to position
  Future<void> seek(Duration position) => _seekImpl(position);

  Future<void> startCastingToDevice(GoogleCastDevice device) =>
      _startCastingToDeviceImpl(device);

  Future<void> stopCastingAndResumeLocal() => _stopCastingAndResumeLocalImpl();

  /// Toggle shuffle mode
  void toggleShuffle() => _toggleShuffleImpl();

  /// Reorder queue after a drag in the queue screen's "current first" display order.
  /// Indices match [ReorderableListView] after the usual `newIndex -= 1` adjustment when moving down.
  /// The playing track stays pinned at display index 0.
  void reorderQueueFromDisplayOrder(int oldDisplayIndex, int newDisplayIndex) =>
      _reorderQueueFromDisplayOrderImpl(oldDisplayIndex, newDisplayIndex);

  /// Toggle repeat mode (cycles through none → all → one)
  void toggleRepeat() => _toggleRepeatImpl();

  /// Clear the queue and stop playback
  Future<void> clearQueue() => _clearQueueImpl();

  /// Internal: Play the current song in the queue
  Future<void> _playCurrentSong({
    bool autoPlay = true,
    bool restartStatsTracking = true,
    bool isResume = false,
  }) =>
      _playCurrentSongImpl(
        autoPlay: autoPlay,
        restartStatsTracking: restartStatsTracking,
        isResume: isResume,
      );

  Future<void> _restoreLocalPlaybackSnapshot(_PlaybackHandoffState snapshot) =>
      _restoreLocalPlaybackSnapshotImpl(snapshot);

  Future<bool> _verifyLocalResumeProgress(Duration expectedPosition) =>
      _verifyLocalResumeProgressImpl(expectedPosition);

  Future<void> _reloadLocalPlaybackFromSnapshot(
          _PlaybackHandoffState snapshot) =>
      _reloadLocalPlaybackFromSnapshotImpl(snapshot);

  /// Internal: Cache a song in the background for future offline playback
  void _cacheSongInBackground(Song song) => _cacheSongInBackgroundImpl(song);

  /// Internal: Get stream URL with retry-once logic for expired stream tokens
  ///
  /// For authenticated streaming, if the stream ticket request fails with
  /// STREAM_TOKEN_EXPIRED, this method will retry once with a fresh token.
  Future<String> _getStreamUrlWithRetry(Song song, StreamingQuality quality) =>
      _getStreamUrlWithRetryImpl(song, quality);

  String? _extractStreamToken(String url) => _extractStreamTokenImpl(url);

  /// Internal: Find the next available song in the queue (starting from current index + 1)
  /// Returns the index of the next available song, or null if none found
  Future<int?> _findNextAvailableSongIndex() =>
      _findNextAvailableSongIndexImpl();

  /// Internal: Find the next available song starting from a specific index
  /// Used when wrapping around in repeat-all mode
  Future<int?> _findNextAvailableSongIndexFrom(int startIndex) =>
      _findNextAvailableSongIndexFromImpl(startIndex);

  /// Internal: Find the previous available song in the queue (starting from current index - 1)
  /// Returns the index of the previous available song, or null if none found
  Future<int?> _findPreviousAvailableSongIndex() =>
      _findPreviousAvailableSongIndexImpl();

  /// Internal: Handle song completion
  Future<void> _onSongCompleted() => _onSongCompletedImpl();

  /// Save current playback state to device storage
  Future<void> _saveState() => _saveStateImpl();

  /// Public helper for callers that need to guarantee the state is flushed
  Future<void> saveStateImmediately() => _saveStateImmediatelyImpl();

  /// Restore saved playback state from device storage
  Future<void> _restoreState() => _restoreStateImpl();

  void _invalidatePendingRestore(String reason) =>
      _invalidatePendingRestoreImpl(reason);

  Future<List<Song>> _rehydrateSongs(List<Song> songs) =>
      _rehydrateSongsImpl(songs);

  Song _rehydrateSong(
    Song song, {
    SongModel? librarySong,
    Song? downloadedSong,
  }) =>
      _rehydrateSongImpl(
        song,
        librarySong: librarySong,
        downloadedSong: downloadedSong,
      );

  void _updateCurrentSongDuration(Duration duration) =>
      _updateCurrentSongDurationImpl(duration);

  void _notifyStateChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _isInitialized = false;
    _castService.removeListener(_onCastStateChanged);
    _castStatsForwardTimer?.cancel();
    _saveTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPreviousSubscription?.cancel();
    super.dispose();
  }
}
