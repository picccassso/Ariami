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
  StreamSubscription<double>? _volumeSubscription;

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
  }) {
    if (remote == null) {
      _connectSuppressedAt = null;
      _connectSuppressionTimer?.cancel();
      _connectSuppressionTimer = null;
    }
    if (remote != null && _connectSuppressedAt != null) {
      final sinceIntent = DateTime.now().difference(_connectSuppressedAt!);
      if (sinceIntent < _connectSuppression) {
        _connectSuppressionTimer?.cancel();
        _connectSuppressionTimer = Timer(
          _connectSuppression - sinceIntent,
          () {
            _connectSuppressionTimer = null;
            _connectSuppressedAt = null;
            setConnectRemoteMirror(remote, sendCommand: sendCommand);
          },
        );
        return;
      }
      _connectSuppressedAt = null;
    }
    _sendConnectCommand = sendCommand ?? _sendConnectCommand;
    final unchanged = identical(_connectRemote?.snapshot, remote?.snapshot) &&
        _connectRemote?.deviceId == remote?.deviceId;
    _connectRemote = remote;
    if (remote == null) {
      _sendConnectCommand = null;
      _connectRemoteSongs = const <Song>[];
      _connectRemoteQueue = null;
    } else {
      _connectRemoteSongs = remote.snapshot.queue
          .map(_songFromConnectJson)
          .whereType<Song>()
          .toList(growable: false);
      _connectRemoteQueue = PlaybackQueue(
        songs: List<Song>.from(_connectRemoteSongs),
        currentIndex: _connectRemoteSongs.isEmpty
            ? 0
            : remote.snapshot.currentIndex
                .clamp(0, _connectRemoteSongs.length - 1),
      );
    }
    _syncConnectTicker();
    if (!unchanged) notifyListeners();
  }

  /// Hides the mirror immediately when the user starts playback locally, ahead
  /// of the hub confirming the takeover.
  void _suppressConnectMirror() {
    _connectSuppressionTimer?.cancel();
    _connectSuppressionTimer = null;
    _connectSuppressedAt = DateTime.now();
    if (_connectRemote == null) return;
    _connectRemote = null;
    _connectRemoteSongs = const <Song>[];
    _connectRemoteQueue = null;
    _sendConnectCommand = null;
    _syncConnectTicker();
  }

  /// Keeps the mirrored seek bar moving between remote state broadcasts.
  void _syncConnectTicker() {
    final ticking = _connectRemote?.snapshot.isPlaying ?? false;
    if (ticking && !(_connectTicker?.isActive ?? false)) {
      _connectTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else if (!ticking) {
      _connectTicker?.cancel();
      _connectTicker = null;
    }
  }

  void _sendConnect(String command, [Map<String, dynamic>? arguments]) =>
      _sendConnectCommand?.call(command, arguments);

  /// Sends a whole new queue to the active device (Spotify-style: browsing on
  /// a controller starts music on the remote player, not here).
  void _sendConnectPlayContext(
    List<Song> songs, {
    int currentIndex = 0,
    required bool shuffle,
  }) {
    final remote = _connectRemote;
    if (remote == null || songs.isEmpty) return;
    final start = currentIndex.clamp(0, songs.length - 1);
    final snapshot = AriamiPlaybackSnapshot(
      queue: songs.map((song) => song.toJson()).toList(growable: false),
      currentIndex: start,
      positionMs: 0,
      durationMs: songs[start].duration.inMilliseconds,
      isPlaying: true,
      shuffle: shuffle,
      repeatMode:
          repeatModeAfterExplicitTrackChange(remote.snapshot.repeatMode),
      volume: remote.snapshot.volume,
    );
    _sendConnect(AriamiConnectCommand.playContext, <String, dynamic>{
      'snapshot': snapshot.toJson(),
    });
    // Mirror the new context optimistically; the active device's own state
    // broadcast confirms it.
    setConnectRemoteMirror(remote.copyWithSnapshot(snapshot));
  }

  /// Applies an optimistic local adjustment to the mirrored snapshot so the UI
  /// responds instantly; the active device's next broadcast is authoritative.
  void _applyConnectOptimistic({bool? isPlaying, int? positionMs}) {
    final remote = _connectRemote;
    if (remote == null) return;
    _connectRemote = remote.copyWithSnapshot(remote.snapshot.copyWith(
      // Re-anchor at the currently extrapolated position so toggling
      // play/pause doesn't rewind the bar to the last broadcast position.
      positionMs: positionMs ?? remote.positionMs,
      isPlaying: isPlaying,
    ));
    _syncConnectTicker();
    notifyListeners();
  }

  /// Runs a Connect command against the local engine, bypassing the remote
  /// mirror. The hub only routes commands here for this device's own playback
  /// (including the takeover pause sent to a device that just lost the
  /// session), so they must never bounce back out as remote commands.
  Future<void> handleConnectCommand(
    String command,
    Map<String, dynamic> arguments,
  ) async {
    switch (command) {
      case AriamiConnectCommand.play:
        if (!_localIsPlaying) await _togglePlayPauseImpl();
      case AriamiConnectCommand.pause:
        if (_localIsPlaying) await _togglePlayPauseImpl();
      case AriamiConnectCommand.toggle:
        await _togglePlayPauseImpl();
      case AriamiConnectCommand.next:
        await _skipNextImpl(completedNaturally: false);
      case AriamiConnectCommand.previous:
        await _skipPreviousImpl();
      case AriamiConnectCommand.seek:
        await _seekImpl(Duration(
          milliseconds: (arguments['positionMs'] as num?)?.toInt() ?? 0,
        ));
      case AriamiConnectCommand.toggleShuffle:
        _toggleShuffleImpl();
      case AriamiConnectCommand.cycleRepeat:
        _toggleRepeatImpl();
      case AriamiConnectCommand.playQueueIndex:
        await _skipToQueueItemImpl(
          (arguments['index'] as num?)?.toInt() ?? -1,
        );
      case AriamiConnectCommand.playContext:
        final raw = arguments['snapshot'];
        if (raw is Map) {
          final snapshot = AriamiPlaybackSnapshot.fromJson(
            Map<String, dynamic>.from(raw),
          );
          await applyConnectSnapshot(
            snapshot.copyWith(
              repeatMode:
                  repeatModeAfterExplicitTrackChange(snapshot.repeatMode),
            ),
          );
        }
    }
  }

  /// Always pauses this device's own playback (local or cast), bypassing the
  /// remote mirror; used for Connect handoffs.
  Future<void> pauseLocal() async {
    if (_localIsPlaying) await _togglePlayPauseImpl();
  }

  Future<void> applyConnectSnapshot(AriamiPlaybackSnapshot snapshot) async {
    final songs = snapshot.queue
        .map(_songFromConnectJson)
        .whereType<Song>()
        .toList(growable: false);
    if (songs.isEmpty) return;
    await _audioPlayer.pause();
    _invalidatePendingRestore('ariami-connect');
    _queue = PlaybackQueue(
      songs: songs,
      currentIndex: snapshot.currentIndex.clamp(0, songs.length - 1),
    );
    _oneShotQueuedSongs.clear();
    _shuffleService.reset();
    _isShuffleEnabled = snapshot.shuffle;
    _repeatMode = switch (snapshot.repeatMode) {
      'all' => RepeatMode.all,
      'one' => RepeatMode.one,
      _ => RepeatMode.none,
    };
    _restoredPosition = Duration(milliseconds: snapshot.positionMs);
    _pendingUiPosition = _restoredPosition;
    await _playCurrentSong(autoPlay: snapshot.isPlaying);
    await _saveState();
    notifyListeners();
  }

  Song? _songFromConnectJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final durationSeconds = (json['duration'] as num?)?.toInt() ??
        (((json['durationMs'] as num?)?.toInt() ?? 0) ~/ 1000);
    return Song(
      id: id,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String?,
      albumId: json['albumId'] as String?,
      albumArtist: json['albumArtist'] as String?,
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      genre: json['genre'] as String?,
      duration: Duration(seconds: durationSeconds),
      filePath: json['filePath'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Initialize the playback manager and set up listeners
  void initialize() {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;
    _queue = PlaybackQueue();
    _oneShotQueuedSongs.clear();
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
      if (!_castService.isConnected) {
        _statsService.setPlaybackActive(
          state.playing && state.processingState == ProcessingState.ready,
        );
      }
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

    _seekSubscription = _audioPlayer.seekStream.listen((_) {
      _statsService.markPositionDiscontinuity();
    });

    // Mute when silent, unmute when unsilenced: pause local playback when the
    // system media volume reaches zero and resume it when raised back up.
    // Pass the playback category so the iOS listener keeps the audio session
    // compatible with audio_service's background playback session.
    _volumeSubscription = FlutterVolumeController.addListener(
      _onSystemVolumeChanged,
      category: AudioSessionCategory.playback,
    );

    // Set up periodic save timer for position updates
    _saveTimer = Timer.periodic(_saveDebounceDuration, (_) async {
      if (currentSong != null && isPlaying) {
        await _saveState();
      }
    });

    // Restore saved state
    _restoreState();
  }

  /// React to system media-volume changes for the "mute when silent" feature.
  ///
  /// When the volume drops to zero we pause local playback (so the track does
  /// not keep advancing inaudibly) and remember that we did so. When the volume
  /// is raised again we resume — but only if the pause was ours, never after a
  /// manual pause. Casting has its own volume control, so we leave it alone.
  void _onSystemVolumeChanged(double volume) {
    if (_castService.isConnected) {
      return;
    }

    // outputVolume can report tiny non-zero values; treat near-zero as silent.
    final isSilent = volume <= 0.0001;

    if (isSilent) {
      if (_audioPlayer.isPlaying && !_pausedBySilence) {
        _pausedBySilence = true;
        unawaited(() async {
          try {
            await _statsService.onSongStopped();
            await _audioPlayer.pause();
            await _saveState();
            _notifyStateChanged();
          } catch (e) {
            print('[PlaybackManager] Error pausing for silence: $e');
          }
        }());
      }
    } else if (_pausedBySilence) {
      _pausedBySilence = false;
      if (currentSong != null && !_audioPlayer.isPlaying) {
        unawaited(() async {
          try {
            _statsService.onSongStarted(currentSong!, isResume: true);
            await _audioPlayer.resume();
            _notifyStateChanged();
          } catch (e) {
            print('[PlaybackManager] Error resuming after silence: $e');
          }
        }());
      }
    }
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
      audioHandler?.exitCastMode();
      _lastObservedCastPlayerState = null;
      _castStatsForwardTimer?.cancel();
      _castStatsForwardTimer = null;
      _statsService.setPlaybackActive(false);
      notifyListeners();
      return;
    }

    _statsService.setPlaybackActive(
      _castService.isRemotePlaying && !_castService.isRemoteBuffering,
    );

    audioHandler?.updateCastPlaybackState(
      position: _castService.remotePosition,
      isPlaying: _castService.isRemotePlaying,
      duration: _castService.remoteDuration ?? currentSong?.duration,
      isBuffering: _castService.isRemoteBuffering,
    );

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
  void addAllToQueue(List<Song> songs) => _addAllToQueueImpl(songs);

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
  /// Editing a mirrored (remote) queue is not supported.
  Future<void> removeQueueItem(int index) async {
    if (_connectRemote != null) return;
    await _removeQueueItemImpl(index);
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

  /// Clear the queue and stop playback.
  /// Editing a mirrored (remote) queue is not supported.
  Future<void> clearQueue() async {
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
    _volumeSubscription?.cancel();
    FlutterVolumeController.removeListener();
    super.dispose();
  }
}
