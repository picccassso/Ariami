import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import '../models/song.dart';
import '../models/playback_queue.dart';
import '../models/quality_settings.dart';
import '../models/repeat_mode.dart';
import '../models/api_models.dart';
import '../models/download_task.dart';
import 'audio/audio_player_service.dart';
import 'audio/audio_handler.dart';
import 'audio/gapless_playback_service.dart';
import 'audio/shuffle_service.dart';
import 'audio/playback_state_manager.dart';
import 'api/connection_service.dart';
import 'api/api_client.dart';
import 'download/download_manager.dart';
import 'library/library_repository.dart';
import 'cast/chrome_cast_service.dart';
import 'offline/offline_playback_service.dart';
import 'cache/cache_manager.dart';
import 'media/media_request_scheduler.dart';
import 'stats/streaming_stats_service.dart';
import 'color_extraction_service.dart';
import 'quality/quality_settings_service.dart';
import 'library/album_metadata_resolver.dart';
import '../main.dart' show audioHandler;

part 'playback_manager_queue_impl.dart';
part 'playback_manager_casting_impl.dart';
part 'playback_manager_connect_impl.dart';
part 'playback_manager_lifecycle_impl.dart';
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
  final GaplessPlaybackService _gaplessPlayback = GaplessPlaybackService();
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
  final HashSet<Song> _oneShotQueuedSongs = HashSet<Song>.identity();
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.none;

  // Stream subscriptions
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription<void>? _skipNextSubscription;
  StreamSubscription<void>? _skipPreviousSubscription;
  StreamSubscription<Duration>? _seekSubscription;
  StreamSubscription<GaplessPlaybackTransition>? _gaplessTransitionSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription? _networkTypeSubscription;
  StreamSubscription<Duration>? _bufferedPositionSubscription;

  // True when local playback was auto-paused because the device media volume
  // dropped to zero ("mute when silent"). Used to auto-resume when the volume
  // is raised again, and only then — a manual pause must not auto-resume.
  bool _pausedBySilence = false;

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
  String? _lastWarmupKey;
  int _gaplessRefreshGeneration = 0;
  bool _isHandlingGaplessTransition = false;
  String? _deferredGaplessSongId;

  // Consecutive auto-skips over songs that no longer exist in the server
  // library. Reset whenever a song actually starts; caps the skip chain so a
  // queue made entirely of stale ids stops instead of cycling forever.
  int _unplayableSkipStreak = 0;
  final StreamController<Song> _unplayableSongController =
      StreamController<Song>.broadcast();

  /// Songs that were auto-skipped because they no longer exist in the server
  /// library (stale playlist ids). The app shell listens and surfaces a
  /// snackbar naming the track.
  Stream<Song> get unplayableSongStream => _unplayableSongController.stream;

  // Getters
  //
  // Chromecast and the Ariami Connect mirror both overlay the local engine:
  // casting is still *this* device's session (it publishes to Connect), while
  // the Connect mirror reflects playback owned by another signed-in device.
  Song? get currentSong {
    final remote = _connectRemote;
    if (remote != null) {
      final index = remote.snapshot.currentIndex;
      if (index < 0 || index >= _connectRemoteSongs.length) return null;
      return _connectRemoteSongs[index];
    }
    return _localCurrentSong;
  }

  bool get isPlaying => _connectRemote?.snapshot.isPlaying ?? _localIsPlaying;
  bool get isLoading => _connectRemote != null
      ? false
      : (_castService.isConnected
          ? _castService.isRemoteBuffering
          : _audioPlayer.isLoading);
  Duration get position => _connectRemote != null
      ? Duration(milliseconds: _connectRemote!.positionMs)
      : _localPosition;
  Duration? get duration {
    final remote = _connectRemote;
    if (remote == null) return _localDuration;
    if (remote.snapshot.durationMs > 0) {
      return Duration(milliseconds: remote.snapshot.durationMs);
    }
    return currentSong?.duration;
  }

  bool get isShuffleEnabled =>
      _connectRemote?.snapshot.shuffle ?? _isShuffleEnabled;
  RepeatMode get repeatMode {
    final remote = _connectRemote;
    if (remote == null) return _repeatMode;
    return switch (remote.snapshot.repeatMode) {
      'all' => RepeatMode.all,
      'one' => RepeatMode.one,
      _ => RepeatMode.none,
    };
  }

  PlaybackQueue get queue => _connectRemoteQueue ?? _queue;
  bool get hasNext {
    final remote = _connectRemote;
    if (remote != null) {
      return remote.snapshot.repeatMode != 'off' ||
          remote.snapshot.currentIndex < remote.snapshot.queue.length - 1;
    }
    return _queue.hasNext ||
        (_queue.isNotEmpty && _repeatMode.allowsBoundaryRestart);
  }

  bool get hasPrevious {
    // Previous on the remote device at worst restarts its current track.
    if (_connectRemote != null) return true;
    return _queue.hasPrevious ||
        (_queue.isNotEmpty && _repeatMode.allowsBoundaryRestart);
  }

  bool get isCastTransitionInProgress => _isCastTransitionInProgress;

  // Local (non-mirrored) values: published Connect snapshots and takeover
  // detection must describe this device's own playback (including an active
  // Chromecast session it drives) even while the UI mirrors another device.
  Song? get localCurrentSong => _localCurrentSong;
  bool get localIsPlaying => _localIsPlaying;

  Song? get _localCurrentSong => _queue.currentSong;
  bool get _localIsPlaying => _castService.isConnected
      ? _castService.isRemotePlaying
      : _audioPlayer.isPlaying;
  Duration get _localPosition => _castService.isConnected
      ? _castService.remotePosition
      : (_pendingUiPosition ?? _audioPlayer.position);
  Duration? get _localDuration => _castService.isConnected
      ? (_castService.remoteDuration ?? _queue.currentSong?.duration)
      : (_audioPlayer.duration ?? _queue.currentSong?.duration);

  AriamiPlaybackSnapshot get connectSnapshot => AriamiPlaybackSnapshot(
        queue:
            _queue.songs.map((song) => song.toJson()).toList(growable: false),
        currentIndex: _queue.isEmpty ? -1 : _queue.currentIndex,
        positionMs: _localPosition.inMilliseconds,
        durationMs:
            (_localDuration ?? _localCurrentSong?.duration ?? Duration.zero)
                .inMilliseconds,
        isPlaying: _localIsPlaying,
        shuffle: _isShuffleEnabled,
        repeatMode: _repeatMode == RepeatMode.none ? 'off' : _repeatMode.name,
        volume: 1,
      );

  // Ariami Connect remote mirroring ------------------------------------------
  //
  // While another device is the active Connect player, the getters above
  // mirror that device's queue and transport state (Spotify Connect-style) and
  // every transport method turns into a Connect command. The local queue stays
  // intact underneath and reappears when the mirror lifts.
  AriamiRemotePlayback? _connectRemote;
  List<Song> _connectRemoteSongs = const <Song>[];
  PlaybackQueue? _connectRemoteQueue;
  void Function(String command, [Map<String, dynamic>? arguments])?
      _sendConnectCommand;
  Timer? _connectTicker;
  Timer? _connectSuppressionTimer;
  DateTime? _connectSuppressedAt;

  /// How long a local play intent keeps the mirror off while the takeover
  /// publish round-trips through the hub.
  static const _connectSuppression = Duration(seconds: 5);

  /// True while this device is showing (and remote-controlling) playback that
  /// runs on another Connect device.
  bool get isConnectRemoteActive => _connectRemote != null;
  String? get connectRemoteDeviceName => _connectRemote?.deviceName;

  /// Wires (or clears) the remote mirror. Called by the Connect controller on
  /// every hub update; [remote] is null whenever this device is the active
  /// player or no remote session exists.
  void setConnectRemoteMirror(
    AriamiRemotePlayback? remote, {
    void Function(String command, [Map<String, dynamic>? arguments])?
        sendCommand,
  }) =>
      _setConnectRemoteMirrorImpl(remote, sendCommand: sendCommand);

  /// Runs a Connect command against the local engine, bypassing the remote
  /// mirror.
  Future<void> handleConnectCommand(
    String command,
    Map<String, dynamic> arguments,
  ) =>
      _handleConnectCommandImpl(command, arguments);

  /// Always pauses this device's own playback (local or cast), bypassing the
  /// remote mirror; used for Connect handoffs.
  Future<void> pauseLocal() => _pauseLocalImpl();

  Future<void> applyConnectSnapshot(AriamiPlaybackSnapshot snapshot) =>
      _applyConnectSnapshotImpl(snapshot);

  /// Initialize the playback manager and set up listeners.
  void initialize() => _initializeImpl();

  /// Play a single song immediately (clears queue and starts fresh).
  /// While another device owns the Connect session, browsing here plays there;
  /// otherwise starting music is an implicit takeover.
  Future<void> playSong(Song song) {
    if (_connectRemote != null) {
      _sendConnectPlayContext([song], shuffle: false);
      return Future.value();
    }
    _suppressConnectMirror();
    return _playSongImpl(song);
  }

  /// Plays a one-song context that wraps back to the same song.
  ///
  /// This keeps Recently Played independent from the previous queue while
  /// making both natural completion and an explicit skip deterministic.
  Future<void> playSingleRepeated(Song song) {
    if (_connectRemote != null) {
      _sendConnectPlayContext(
        [song],
        shuffle: false,
        forceRepeatAll: true,
      );
      return Future.value();
    }
    _suppressConnectMirror();
    return _playSongImpl(song, forceRepeatAll: true);
  }

  /// Play a list of songs starting at a specific index
  Future<void> playSongs(List<Song> songs, {int startIndex = 0}) {
    if (_connectRemote != null) {
      _sendConnectPlayContext(songs, currentIndex: startIndex, shuffle: false);
      return Future.value();
    }
    _suppressConnectMirror();
    return _playSongsImpl(songs, startIndex: startIndex);
  }

  /// Play all songs and shuffle if requested
  Future<void> playShuffled(List<Song> songs) {
    if (_connectRemote != null) {
      _sendConnectPlayContext(
        List<Song>.from(songs)..shuffle(),
        shuffle: true,
      );
      return Future.value();
    }
    _suppressConnectMirror();
    return _playShuffledImpl(songs);
  }

  /// Add song to end of queue
  void addToQueue(Song song) => _addToQueueImpl(song);

  /// Add multiple songs to queue
  void addAllToQueue(List<Song> songs) {
    if (songs.isEmpty) return;
    final remote = _connectRemote;
    if (remote != null) {
      _appendConnectQueue(remote, songs);
      return;
    }
    _addAllToQueueImpl(songs);
  }

  /// Insert song to play next
  void playNext(Song song) => _playNextImpl(song);

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    final remote = _connectRemote;
    if (remote != null) {
      _sendConnect(AriamiConnectCommand.toggle);
      _applyConnectOptimistic(isPlaying: !remote.snapshot.isPlaying);
      return;
    }
    await _togglePlayPauseImpl();
  }

  /// Skip to next song
  Future<void> skipNext() async {
    if (_connectRemote != null) {
      _sendConnect(AriamiConnectCommand.next);
      return;
    }
    await _skipNextImpl(completedNaturally: false);
  }

  /// Skip to previous song
  Future<void> skipPrevious() async {
    if (_connectRemote != null) {
      _sendConnect(AriamiConnectCommand.previous);
      return;
    }
    await _skipPreviousImpl();
  }

  /// Skip to a specific queue item
  Future<void> skipToQueueItem(int index) async {
    if (_connectRemote != null) {
      // The mirrored queue mirrors the active device's published order, so
      // the index maps 1:1 onto that device's snapshot.
      _sendConnect(AriamiConnectCommand.playQueueIndex, <String, dynamic>{
        'index': index,
      });
      return;
    }
    await _skipToQueueItemImpl(index);
  }

  /// Remove a queue item and keep playback/UI state in sync.
  /// Returns a snapshot for [undoRemoveQueueItem], or null if nothing was removed.
  /// On a mirrored (remote) queue this routes the edit to the active device.
  Future<QueueItemRemoval?> removeQueueItem(int index) async {
    final remote = _connectRemote;
    if (remote != null) return _removeConnectQueueItem(remote, index);
    return _removeQueueItemImpl(index);
  }

  /// Re-insert a song removed by [removeQueueItem] at its old position.
  /// A remote removal is undone on the active device it was sent to.
  Future<void> undoRemoveQueueItem(QueueItemRemoval removal) async {
    if (removal.wasRemote) {
      _undoConnectQueueRemoval(removal);
      return;
    }
    if (_connectRemote != null) return;
    await _undoRemoveQueueItemImpl(removal);
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (_connectRemote != null) {
      _sendConnect(AriamiConnectCommand.seek, <String, dynamic>{
        'positionMs': position.inMilliseconds,
      });
      _applyConnectOptimistic(positionMs: position.inMilliseconds);
      return;
    }
    await _seekImpl(position);
  }

  Future<void> startCastingToDevice(GoogleCastDevice device) =>
      _startCastingToDeviceImpl(device);

  Future<void> stopCastingAndResumeLocal() => _stopCastingAndResumeLocalImpl();

  /// Toggle shuffle mode
  void toggleShuffle() {
    if (_connectRemote != null) {
      _sendConnect(AriamiConnectCommand.toggleShuffle);
      return;
    }
    _toggleShuffleImpl();
  }

  /// Reorder queue after a drag in the queue screen's "current first" display order.
  /// Indices match [ReorderableListView] after the usual `newIndex -= 1` adjustment when moving down.
  /// The playing track stays pinned at display index 0.
  /// Editing a mirrored (remote) queue is not supported.
  void reorderQueueFromDisplayOrder(int oldDisplayIndex, int newDisplayIndex) {
    if (_connectRemote != null) return;
    _reorderQueueFromDisplayOrderImpl(oldDisplayIndex, newDisplayIndex);
  }

  /// Toggle repeat mode (cycles through none → all → one)
  void toggleRepeat() {
    if (_connectRemote != null) {
      _sendConnect(AriamiConnectCommand.cycleRepeat);
      return;
    }
    _toggleRepeatImpl();
  }

  /// Clears every queued item except the currently playing song.
  Future<void> clearQueue() async {
    final remote = _connectRemote;
    if (remote != null) {
      _clearConnectQueue(remote);
      return;
    }
    await _clearUpcomingImpl();
  }

  /// Stops playback and removes the complete queue during a local-data reset.
  Future<void> stopAndClearQueue() async {
    if (_connectRemote != null) return;
    await _clearQueueImpl();
  }

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

  void _warmNextStreamInBackground(StreamingQuality quality) =>
      _warmNextStreamInBackgroundImpl(quality);

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

  void _onGaplessPreferenceChanged() {
    unawaited(_refreshGaplessQueue());
  }

  Future<void> _refreshGaplessQueue() => _refreshGaplessQueueImpl();

  Future<void> _handleGaplessTransition(
    GaplessPlaybackTransition transition,
  ) =>
      _handleGaplessTransitionImpl(transition);

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

  void _useRepeatAllForNewSongSelection() {
    _repeatMode = _repeatMode.forNewSongSelection;
  }

  void _enterCastNotificationMode(Song song, bool isPlaying) {
    final payload = _castService.lastSyncPayload;
    if (payload == null) {
      return;
    }

    audioHandler?.enterCastMode(
      song,
      payload.streamUrl,
      payload.artworkUri,
      payload.position,
      isPlaying,
    );
  }

  @override
  void dispose() {
    _isInitialized = false;
    _castService.removeListener(_onCastStateChanged);
    _castStatsForwardTimer?.cancel();
    _connectTicker?.cancel();
    _connectSuppressionTimer?.cancel();
    _saveTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPreviousSubscription?.cancel();
    _seekSubscription?.cancel();
    _gaplessTransitionSubscription?.cancel();
    _gaplessPlayback.removeListener(_onGaplessPreferenceChanged);
    _volumeSubscription?.cancel();
    _networkTypeSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _unplayableSongController.close();
    FlutterVolumeController.removeListener();
    super.dispose();
  }
}
