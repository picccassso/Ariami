import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_core/utils/play_next_position.dart';
import 'package:ariami_core/utils/playback_operation_guard.dart';

import '../models/player_models.dart';
import 'audio/gapless_playback_service.dart';
import 'playback_quality_policy.dart';
import 'player_api_client.dart';
import 'player_host.dart';

part 'audio_controller/audio_controller_remote.dart';
part 'audio_controller/audio_controller_persistence.dart';
part 'audio_controller/audio_controller_player_events.dart';
part 'audio_controller/audio_controller_sources.dart';
part 'audio_controller/audio_controller_local_playback.dart';
part 'audio_controller/audio_controller_queue_undo.dart';

enum PlayerRepeatMode { off, all, one }

/// Puts back what a queue action changed (see
/// [AudioController.queueReplacedStream] and
/// [AudioController.removeUpcomingAll]).
typedef QueueUndo = Future<void> Function();

/// Owns audio playback and the play queue.
///
/// Uses [just_audio] under the hood (native AVPlayer on macOS). Tracks are
/// streamed from the server via short-lived stream tickets, so each load
/// requests a fresh token.
class AudioController extends ChangeNotifier {
  static const Set<String> connectSupportedCommands =
      AriamiConnectCommand.supported;

  /// Converts a linear UI volume in the range [0.0, 1.0] to a perceptual
  /// audio gain (cubic taper) for the underlying player engine. Human hearing
  /// perceives sound intensity logarithmically, so linear gain mapping leaves
  /// audio loud at 20% and compresses useful low-volume control into the bottom
  /// 1-2% of the slider.
  static double volumeToGain(double linearVolume) {
    final clamped = linearVolume.clamp(0.0, 1.0);
    return clamped * clamped * clamped;
  }

  /// Inverts [volumeToGain] back to a linear volume in [0.0, 1.0].
  static double gainToVolume(double gain) {
    final clamped = gain.clamp(0.0, 1.0);
    return clamped <= 0.0 ? 0.0 : pow(clamped, 1.0 / 3.0).toDouble();
  }

  factory AudioController({AudioPlayer? player, PlayerHost? host}) {
    final effectivePlayer = player ??
        host?.createAudioPlayer?.call() ??
        AudioPlayer(useLazyPreparation: !kIsWeb);
    return AudioController._(effectivePlayer, host);
  }

  AudioController._(this._player, this._host) : _castService = _host?.cast {
    _wireStreams();
    _gapless.addListener(_onGaplessPreferenceChanged);
    _castService?.addListener(_onCastServiceChanged);
    _castService?.onTrackCompleted = _onCastTrackCompleted;
  }

  final AudioPlayer _player;
  final PlayerHost? _host;
  final GaplessPlaybackService _gapless = GaplessPlaybackService();
  final PlayerCastBridge? _castService;
  PlayerApiClient? _client;

  PlayerCastBridge? get castService => _castService;
  bool get isCastActive => _castService?.isConnected ?? false;
  String? get castDeviceName => _castService?.connectedDeviceName;

  void _onCastServiceChanged() => notifyListeners();

  void _onCastTrackCompleted() {
    debugPrint(
      '[AudioController] _onCastTrackCompleted invoked | '
      'isCastActive=$isCastActive, remote=${_remote != null}, '
      'orderPos=$_orderPos, queueLen=${_playOrder.length}, repeat=$_repeat',
    );
    if (!isCastActive || _remote != null) return;
    unawaited(() async {
      if (_repeat == PlayerRepeatMode.one) {
        debugPrint('[AudioController] Repeating one track on cast');
        await _loadCurrent(autoplay: true);
      } else if (_orderPos < _playOrder.length - 1) {
        _orderPos++;
        debugPrint(
            '[AudioController] Advancing cast to track index $_orderPos: ${currentTrack?.title}');
        await _loadCurrent(autoplay: true);
      } else if (_repeat == PlayerRepeatMode.all && _playOrder.isNotEmpty) {
        _orderPos = 0;
        debugPrint('[AudioController] Looping all tracks on cast');
        await _loadCurrent(autoplay: true);
      } else {
        debugPrint('[AudioController] End of queue reached on cast; pausing');
        _castService?.pause();
      }
    }());
  }

  final PlaybackQualityPolicy _qualityPolicy = PlaybackQualityPolicy();
  StreamQuality get quality => _qualityPolicy.preferredQuality;
  StreamQuality get effectiveQuality => _qualityPolicy.effectiveQuality;
  bool get isLocalPlayback => _qualityPolicy.isLocalPlayback;

  /// Resolves a song id to a downloaded file on disk (or null). Wired by the
  /// player root to the download controller.
  String? Function(String songId)? localFileResolver;

  /// Resolves a song id to its library file when this desktop hosts the
  /// embedded server (server + client mode). Wired by the player root to the
  /// server's library manager.
  ///
  /// Local playback must never stream over loopback HTTP: the embedded server
  /// runs in the Dart isolate on the app's main thread, and AVFoundation can
  /// block that same thread in a synchronous notification callback while its
  /// asset loader waits for byte-stream data only the server can provide —
  /// a process-wide deadlock that also takes the server down for every other
  /// client. Local playback is pinned to original quality, so playing the
  /// file directly is byte-identical to what /stream would have served.
  String? Function(String songId)? serverFileResolver;

  /// Resolves a song id to a downloaded file whose quality is equal to or
  /// better than the requested stream quality (or null). Wired by the player
  /// root to the download controller. Used while online so an equal-or-better
  /// local copy replaces the network stream (see [preferDownloadedWhenOnline]).
  String? Function(String songId, StreamQuality minQuality)?
      downloadedFileResolver;

  bool _offlinePlayback = false;

  /// Play-order position of an auto-advance that failed while the server was
  /// unreachable (or the track had no downloaded copy offline). Leaving
  /// offline mode retries this position with autoplay, so a track ending
  /// during a connection drop doesn't leave the queue silently stalled.
  int? _resumeOrderPosOnReconnect;

  /// While online, play a downloaded copy instead of streaming when one
  /// exists at equal-or-better quality than the streaming preference. Never
  /// downgrades audio quality; saves the whole stream on remote (Tailscale)
  /// connections. Persisted and opt-in.
  bool _preferDownloadedWhenOnline = false;
  bool get preferDownloadedWhenOnline => _preferDownloadedWhenOnline;

  /// When true, a collection's Play/Shuffle buttons reflect the queue they
  /// started (Spotify-style): while that album or playlist is what's playing,
  /// Play becomes Pause and Shuffle toggles the live queue instead of
  /// restarting it. Opt-in, so by default those buttons always start the
  /// collection from the top.
  bool _playButtonsFollowPlayback = false;
  bool get playButtonsFollowPlayback => _playButtonsFollowPlayback;

  /// "Keep my queue when tapping a song": a tapped track plays now and the
  /// queue carries on after it, the interrupted track resuming where it
  /// stopped. Play and Shuffle buttons still replace the queue.
  bool _keepQueueOnTap = false;
  bool get keepQueueOnTap => _keepQueueOnTap;

  /// "Stack Play next": Play next goes after the earlier Play next picks
  /// still waiting instead of straight after the current track, so picks
  /// play in the order they were chosen. See [playNextPosition].
  bool _stackPlayNext = false;
  bool get stackPlayNext => _stackPlayNext;

  /// The last track Play next inserted locally (a copy, matched by identity),
  /// and the (index, id) of the last one inserted on a remote device.
  Track? _playNextTail;
  (int, String)? _remotePlayNextTail;

  /// The track a play-now interrupted while keeping the queue, and where it
  /// resumes once it plays again (matched by identity).
  Track? _resumeTrack;
  Duration _resumeTrackPosition = Duration.zero;

  /// True while the server is unreachable (or the user chose offline mode):
  /// tracks play from downloaded files instead of stream URLs.
  bool get isOfflinePlayback => _offlinePlayback;

  void setOfflinePlayback(bool value) {
    if (_offlinePlayback == value) return;
    _offlinePlayback = value;
    notifyListeners();
    if (!value && _maybeResumeInterruptedAdvance()) return;
    unawaited(_refreshGaplessTail());
  }

  final List<Track> _queue = <Track>[];
  List<int> _playOrder = <int>[]; // indices into _queue
  int _orderPos = -1; // position within _playOrder

  /// Keeps the mutable playback queue owned by this controller. Copy before
  /// clearing so callers may safely pass a view backed by [_queue] itself.
  void _replaceQueue(Iterable<Track> tracks) {
    final replacement = List<Track>.of(tracks);
    _queue
      ..clear()
      ..addAll(replacement);
  }

  /// Permanently drops backing entries that are no longer reachable from the
  /// play order, then remaps the surviving indices without changing their
  /// resolved playback order. Keeping both structures canonical prevents a
  /// later shuffle or restore from resurrecting removed tracks.
  void _compactQueueToPlayOrder() {
    if (_playOrder.isEmpty) {
      _queue.clear();
      _orderPos = -1;
      return;
    }

    final currentQueueIndex =
        _playOrder[_orderPos.clamp(0, _playOrder.length - 1)];
    final retainedIndices = _playOrder
        .where((index) => index >= 0 && index < _queue.length)
        .toSet();
    final remappedIndices = <int, int>{};
    final compactedQueue = <Track>[];
    for (var index = 0; index < _queue.length; index++) {
      if (!retainedIndices.contains(index)) continue;
      remappedIndices[index] = compactedQueue.length;
      compactedQueue.add(_queue[index]);
    }

    final seen = <int>{};
    final compactedOrder = <int>[];
    for (final oldIndex in _playOrder) {
      final newIndex = remappedIndices[oldIndex];
      if (newIndex != null && seen.add(newIndex)) {
        compactedOrder.add(newIndex);
      }
    }
    _replaceQueue(compactedQueue);
    _playOrder = compactedOrder;
    if (_playOrder.isEmpty) {
      _orderPos = -1;
      return;
    }
    final remappedCurrent = remappedIndices[currentQueueIndex];
    _orderPos = remappedCurrent == null
        ? _orderPos.clamp(0, _playOrder.length - 1)
        : _playOrder.indexOf(remappedCurrent);
  }

  bool _shuffle = false;
  PlayerRepeatMode _repeat = PlayerRepeatMode.off;

  /// Identifies the collection (album/playlist) the current queue was started
  /// from, so the library can show a "now playing" indicator on it. Saved with
  /// the session, so the indicator returns after a restart. Null when playback
  /// didn't originate from a known collection (e.g. a track played from search
  /// or from a filtered list).
  String? _sourceId;

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _autoplayBlocked = false;
  bool get autoplayBlocked => _autoplayBlocked;

  void dismissAutoplayBlocked() {
    if (!_autoplayBlocked) return;
    _autoplayBlocked = false;
    notifyListeners();
  }

  /// Play pressed while the source is still loading; the in-flight load
  /// starts playback when it lands rather than playing into an idle engine.
  bool _pendingAutoplay = false;
  bool _loadInFlight = false;
  String? _errorRecoveryTrackId;
  ProcessingState _lastLocalProcessingState = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration? _duration;
  double _volume = 1.0;
  double _volumeBeforeMute = 1.0;
  String? _errorMessage;

  final _localPlaybackGuard = PlaybackOperationGuard();

  void _invalidateLocalPlayback({bool suspend = false}) {
    _localPlaybackGuard.invalidate(suspend: suspend);
    _loadGeneration++;
    _gaplessTailGeneration++;
    _gaplessTailPending = false;
    _resumeOrderPosOnReconnect = null;
    _pendingAutoplay = false;
    _loadInFlight = false;
  }

  /// True while the source is still being fetched or handed to the engine.
  bool get _awaitingSourceLoad =>
      _loadInFlight ||
      (_isLoading && _player.processingState == ProcessingState.idle);

  /// Remembers a play pressed mid-load; [_loadCurrent] starts playback when
  /// the source lands. Does not invalidate the in-flight load.
  void _deferPlayToLoad() {
    _pendingAutoplay = true;
    notifyListeners();
  }

  int _loadGeneration = 0; // guards against out-of-order async loads
  int _gaplessTailGeneration = 0;
  List<int> _nativePlaylistOrderPositions = <int>[];
  int? _activeNativeIndex;
  bool _settingNativePlaylist = false;

  // Consecutive auto-skips over tracks that no longer exist in the server
  // library. Reset whenever a track actually starts; caps the skip chain so a
  // queue made entirely of stale ids stops instead of cycling forever.
  int _unplayableSkipStreak = 0;
  final StreamController<Track> _unplayableTrackController =
      StreamController<Track>.broadcast();

  /// Tracks that were auto-skipped because they no longer exist in the server
  /// library (stale playlist/queue ids). The shell listens and surfaces a
  /// snackbar naming the track.
  Stream<Track> get unplayableTrackStream => _unplayableTrackController.stream;

  final StreamController<QueueUndo> _queueReplacedController =
      StreamController<QueueUndo>.broadcast();

  /// Emits an undo each time Play or Shuffle replaces a queue that still had
  /// tracks lined up. The shell listens and offers it in a toast.
  Stream<QueueUndo> get queueReplacedStream => _queueReplacedController.stream;

  /// True while a gapless tail is owed but deferred: appending waits until
  /// the current track has [speculativeGaplessHeadroom] of buffered audio, so
  /// preparing the next stream never competes with the one playing (and
  /// playback start never waits on a second stream-ticket round trip).
  bool _gaplessTailPending = false;

  // Ariami Connect remote mirroring -------------------------------------------
  //
  // While another device is the active Connect player, this controller mirrors
  // that device's queue and transport state (Spotify Connect-style): the public
  // getters below reflect the remote snapshot and every transport method turns
  // into a Connect command instead of touching the local audio engine. The
  // local queue stays intact underneath and reappears when the mirror lifts.
  AriamiRemotePlayback? _remote;
  List<Track> _remoteTracks = const <Track>[];
  void Function(String command, [Map<String, dynamic>? arguments])?
      _sendRemoteCommand;
  Timer? _remoteTicker;
  Timer? _remoteVolumeTimer;
  Timer? _remoteSuppressionTimer;
  DateTime? _remoteSuppressedAt;

  /// How long a local play intent keeps the mirror off while the takeover
  /// publish round-trips through the hub, so stale remote state can't flash
  /// back over the track the user just started here.
  static const _remoteSuppression = Duration(seconds: 5);

  /// True while this device is showing (and remote-controlling) playback that
  /// runs on another Connect device.
  bool get isRemoteActive => _remote != null;
  String? get remoteDeviceName => _remote?.deviceName;
  String? get remoteDeviceType => _remote?.deviceType;

  /// The Google Cast device the active Connect device is casting to, if any.
  String? get remoteCastDeviceName => _remote?.snapshot.castDeviceName;

  /// Wires (or clears) the remote mirror. Called by the Connect controller on
  /// every hub update; [remote] is null whenever this device is the active
  /// player or no remote session exists.
  void setRemoteMirror(
    AriamiRemotePlayback? remote, {
    void Function(String command, [Map<String, dynamic>? arguments])?
        sendCommand,
  }) {
    if (remote == null) {
      // The Connect controller calls this when the hub confirms that this
      // device owns playback. The takeover is no longer speculative, so a
      // later transfer away must not inherit the old suppression window.
      _remoteSuppressedAt = null;
      _remoteSuppressionTimer?.cancel();
      _remoteSuppressionTimer = null;
    }
    if (remote != null && _remoteSuppressedAt != null) {
      final sinceIntent = DateTime.now().difference(_remoteSuppressedAt!);
      if (sinceIntent < _remoteSuppression) {
        // Keep the newest rejected snapshot and replay it when suppression
        // expires. Otherwise one early post-handoff update can leave the UI
        // stale indefinitely until another command happens to publish state.
        _remoteSuppressionTimer?.cancel();
        _remoteSuppressionTimer = Timer(
          _remoteSuppression - sinceIntent,
          () {
            _remoteSuppressionTimer = null;
            _remoteSuppressedAt = null;
            setRemoteMirror(remote, sendCommand: sendCommand);
          },
        );
        return;
      }
      _remoteSuppressedAt = null;
    }
    _sendRemoteCommand = sendCommand ?? _sendRemoteCommand;
    final unchanged = identical(_remote?.snapshot, remote?.snapshot) &&
        _remote?.deviceId == remote?.deviceId;
    // Parse the queue before adopting the mirror, tolerating malformed items,
    // so a bad payload can never leave the mirror half-updated.
    final tracks = remote == null
        ? const <Track>[]
        : _tracksFromConnectQueue(remote.snapshot.queue);
    if (remote != null && _remote?.deviceId != remote.deviceId) {
      _invalidateLocalPlayback(suspend: true);
    }
    _remote = remote;
    _remoteTracks = tracks;
    if (remote == null) _sendRemoteCommand = null;
    _syncRemoteTicker();
    if (!unchanged) notifyListeners();
  }

  static const _stateKey = 'player_playback_state_v1';
  static const _volumePreferenceKey = 'player_volume_v1';
  static const _qualityPreferenceKey = 'player_stream_quality_v1';
  static const _preferDownloadedPreferenceKey = 'player_prefer_downloaded_v1';
  static const _playButtonsFollowPlaybackKey =
      'player_play_buttons_follow_playback_v1';
  static const _keepQueueOnTapKey = 'player_keep_queue_on_tap_v1';
  static const _stackPlayNextKey = 'player_stack_play_next_v1';

  /// Minimum spacing between writes so the high-frequency position stream
  /// doesn't hammer SharedPreferences. A trailing timer guarantees the final
  /// state is still captured after the last change.
  static const _saveIntervalMs = 3000;

  SharedPreferences? _prefs;
  bool _restoring = false;
  int _lastSaveMs = 0;
  Timer? _saveTimer;

  // Public getters ------------------------------------------------------------
  //
  // While a remote mirror is active these reflect the other device's playback;
  // the local fields keep this device's own (paused) session underneath.
  List<Track> get queue =>
      _remote != null ? _remoteTracks : List.unmodifiable(_queue);
  bool get shuffle => _remote?.snapshot.shuffle ?? _shuffle;
  PlayerRepeatMode get repeat {
    final remote = _remote;
    if (remote == null) return _repeat;
    return switch (remote.snapshot.repeatMode) {
      'all' => PlayerRepeatMode.all,
      'one' => PlayerRepeatMode.one,
      _ => PlayerRepeatMode.off,
    };
  }

  bool get isPlaying => isCastActive
      ? (_castService?.isRemotePlaying ?? false)
      : (_remote?.snapshot.isPlaying ?? _isPlaying);

  /// True only while audio is actually coming out of this device — not
  /// casting, not mirroring another Connect device.
  bool get isPlayingHere => _isPlaying && !isCastActive && _remote == null;

  bool get isLoading => isCastActive
      ? (_castService?.isRemoteBuffering ?? false)
      : (_remote != null ? false : _isLoading);

  /// The album/playlist the queue was started from, as a namespaced key (see
  /// [albumSource] / [playlistSource]). Null when the source is unknown.
  String? get sourceId =>
      _remote != null ? _remote!.snapshot.sourceId : _sourceId;

  /// Builds the [sourceId] key for an album, so views can compare against it.
  static String albumSource(String albumId) => 'album:$albumId';

  /// Builds the [sourceId] key for a playlist.
  static String playlistSource(String playlistId) => 'playlist:$playlistId';

  /// Builds the [sourceId] key for an artist page's song list.
  static String artistSource(String name) => 'artist:$name';

  /// The [sourceId] key for the whole-library song list.
  static const String allSongsSource = 'songs:all';
  Duration get position => isCastActive
      ? (_castService?.remotePosition ?? Duration.zero)
      : (_remote != null
          ? Duration(milliseconds: _remote!.positionMs)
          : _position);
  Duration get bufferedPosition =>
      (isCastActive || _remote != null) ? Duration.zero : _bufferedPosition;
  Duration? get duration {
    if (isCastActive) {
      return _castService?.remoteDuration ?? currentTrack?.duration;
    }
    final remote = _remote;
    if (remote == null) return _duration;
    if (remote.snapshot.durationMs > 0) {
      return Duration(milliseconds: remote.snapshot.durationMs);
    }
    return currentTrack?.duration;
  }

  double get volume => isCastActive
      ? (_castService?.deviceVolume ?? _volume)
      : (_remote?.snapshot.volume ?? _volume);

  bool get isMuted => volume <= 0.0;
  String? get errorMessage => _errorMessage;

  Track? get currentTrack {
    final remote = _remote;
    if (remote != null) {
      final index = remote.snapshot.currentIndex;
      if (index < 0 || index >= _remoteTracks.length) return null;
      return _remoteTracks[index];
    }
    return _localCurrentTrack;
  }

  Track? get _localCurrentTrack {
    if (_orderPos < 0 || _orderPos >= _playOrder.length) return null;
    final idx = _playOrder[_orderPos];
    if (idx < 0 || idx >= _queue.length) return null;
    return _queue[idx];
  }

  /// Local (non-mirrored) values, for the Connect controller: published
  /// snapshots and takeover detection must describe this device's own engine
  /// even while the UI mirrors another device.
  Track? get localCurrentTrack => _localCurrentTrack;

  /// A relinquished engine must not be mistaken for a new play intent.
  bool get isLocalPlaybackAllowed => !_localPlaybackGuard.isSuspended;

  bool get localIsPlaying =>
      isCastActive ? (_castService?.isRemotePlaying ?? false) : _isPlaying;

  /// This device's own engine position, unaffected by a remote mirror. Used
  /// by listening-stats tracking, which must only ever credit local playback.
  Duration get localPosition => _position;

  /// The local engine's processing state, for the debug overlay.
  ProcessingState get localProcessingState => _player.processingState;

  /// What the engine is actually reading for the current track (local file vs
  /// stream URL, and at what quality), recorded when the source is resolved.
  /// Null while nothing has loaded. Used by the debug overlay.
  PlaybackSourceInfo? _lastSource;
  PlaybackSourceInfo? get lastSource => _lastSource;

  /// The local engine's queue source key, unaffected by a remote mirror.
  /// Listening events only ever credit local playback, so their source
  /// context must come from here rather than [sourceId].
  String? get localSourceId => _sourceId;

  /// Playback order is serialized rather than the backing queue so a shuffled
  /// handoff preserves exactly what the listener expects to hear next.
  AriamiPlaybackSnapshot get connectSnapshot {
    final resolvedOrder = _playOrder
        .where((index) => index >= 0 && index < _queue.length)
        .toList(growable: false);
    final ordered = resolvedOrder
        .map((index) => _queue[index].toConnectJson())
        .toList(growable: false);
    final backingOrder = connectBackingOrderFor(resolvedOrder, _queue.length);
    return AriamiPlaybackSnapshot(
      queue: ordered,
      backingOrder: backingOrder,
      currentIndex:
          ordered.isEmpty ? -1 : _orderPos.clamp(0, ordered.length - 1),
      positionMs: (isCastActive
              ? (_castService?.remotePosition ?? Duration.zero)
              : _position)
          .inMilliseconds,
      durationMs: (isCastActive
              ? (_castService?.remoteDuration ??
                  currentTrack?.duration ??
                  Duration.zero)
              : (_duration ?? _localCurrentTrack?.duration ?? Duration.zero))
          .inMilliseconds,
      isPlaying: isCastActive
          ? (_castService?.isRemotePlaying ?? false)
          : _isPlaying,
      shuffle: _shuffle,
      repeatMode: _repeat.name,
      volume: isCastActive ? (_castService?.deviceVolume ?? _volume) : _volume,
      sourceId: _sourceId,
      castDeviceName: isCastActive ? _castService?.connectedDeviceName : null,
    );
  }

  Future<void> applyConnectSnapshot(AriamiPlaybackSnapshot snapshot) async {
    _invalidateLocalPlayback(suspend: !snapshot.isPlaying);
    if (snapshot.queue.isEmpty) {
      await clear();
      _shuffle = snapshot.shuffle;
      _repeat = switch (snapshot.repeatMode) {
        'all' => PlayerRepeatMode.all,
        'one' => PlayerRepeatMode.one,
        _ => PlayerRepeatMode.off,
      };
      if (!isCastActive) {
        await _player.setVolume(volumeToGain(_volume));
      }
      notifyListeners();
      return;
    }
    _loadGeneration++;
    if (!isCastActive) {
      await _player.pause();
    }
    final resolved = snapshot.queue.map(Track.fromJson).toList(growable: false);
    _replaceQueue(snapshot.backingOrder.map((index) => resolved[index]));
    _playOrder = List<int>.filled(resolved.length, 0, growable: true);
    for (var backingIndex = 0;
        backingIndex < snapshot.backingOrder.length;
        backingIndex++) {
      _playOrder[snapshot.backingOrder[backingIndex]] = backingIndex;
    }
    _orderPos = snapshot.currentIndex.clamp(0, _queue.length - 1);
    _shuffle = snapshot.shuffle;
    _repeat = switch (snapshot.repeatMode) {
      'all' => PlayerRepeatMode.all,
      'one' => PlayerRepeatMode.one,
      _ => PlayerRepeatMode.off,
    };
    _sourceId = snapshot.sourceId;

    final cast = _castService;
    if (snapshot.castDeviceName == null &&
        cast != null &&
        cast.attachedToExistingPlayback) {
      await cast.disconnect(stopReceiver: false);
    }

    var preservedExistingCast = false;
    if (snapshot.castDeviceName != null) {
      if (cast == null) {
        throw StateError('Google Cast is unavailable on this device.');
      }
      final targetName = snapshot.castDeviceName!.trim().toLowerCase();
      if (isCastActive) {
        final sameReceiver =
            cast.connectedDeviceName?.trim().toLowerCase() == targetName;
        if (!sameReceiver || !cast.attachedToExistingPlayback) {
          throw StateError(
            'Stop this laptop\'s current Cast session before handing off.',
          );
        }
        preservedExistingCast = true;
      } else {
        var device = cast.devices.cast<PlayerCastDevice?>().firstWhere(
              (d) => d?.name.trim().toLowerCase() == targetName,
              orElse: () => null,
            );
        if (device == null) {
          final wasDiscoveryActive = cast.isDiscoveryActive;
          if (!wasDiscoveryActive) {
            await cast.startDiscovery();
          }
          final deadline =
              DateTime.now().add(const Duration(milliseconds: 5000));
          while (DateTime.now().isBefore(deadline) && device == null) {
            await Future.delayed(const Duration(milliseconds: 100));
            device = cast.devices.cast<PlayerCastDevice?>().firstWhere(
                  (d) => d?.name.trim().toLowerCase() == targetName,
                  orElse: () => null,
                );
          }
          if (!wasDiscoveryActive) {
            unawaited(cast.stopDiscovery());
          }
        }
        if (device == null) {
          throw StateError(
            'Could not find ${snapshot.castDeviceName} for Cast handoff.',
          );
        }
        await cast.attachToExistingPlayback(device);
        preservedExistingCast = true;
      }
    }

    if (!isCastActive) {
      await _player.setVolume(volumeToGain(_volume));
    }
    if (!preservedExistingCast) {
      await _loadCurrent(
        autoplay: snapshot.isPlaying,
        initialPosition: Duration(milliseconds: snapshot.positionMs),
      );
    }
    if (_errorMessage != null) {
      throw StateError(_errorMessage!);
    }
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
    if (_remote != null) setRemoteMirror(null);
    if (const {
      AriamiConnectCommand.play,
      AriamiConnectCommand.toggle,
      AriamiConnectCommand.next,
      AriamiConnectCommand.previous,
      AriamiConnectCommand.playQueueIndex,
      AriamiConnectCommand.playContext,
    }.contains(command)) {
      _invalidateLocalPlayback();
    } else if (command == AriamiConnectCommand.pause) {
      _invalidateLocalPlayback(suspend: true);
    }
    final cast = _castService;
    if (cast != null && isCastActive) {
      switch (command) {
        case AriamiConnectCommand.play:
          await cast.resume();
        case AriamiConnectCommand.pause:
          await cast.pause();
        case AriamiConnectCommand.toggle:
          cast.isRemotePlaying ? await cast.pause() : await cast.resume();
        case AriamiConnectCommand.next:
          await _nextLocal();
        case AriamiConnectCommand.previous:
          await _previousLocal();
        case AriamiConnectCommand.seek:
          await cast.seek(Duration(
            milliseconds: (arguments['positionMs'] as num?)?.toInt() ?? 0,
          ));
        case AriamiConnectCommand.setVolume:
          await cast.setVolume(
            (arguments['volume'] as num?)?.toDouble() ?? cast.deviceVolume,
          );
        case AriamiConnectCommand.toggleShuffle:
          _toggleShuffleLocal();
        case AriamiConnectCommand.cycleRepeat:
          _cycleRepeatLocal();
        case AriamiConnectCommand.playQueueIndex:
          await _jumpToOrderPositionLocal(
            (arguments['index'] as num?)?.toInt() ?? -1,
          );
        case AriamiConnectCommand.removeQueueIndex:
          await _removeOrderPositionLocal(
            (arguments['index'] as num?)?.toInt() ?? -1,
            arguments['id'] as String?,
          );
        case AriamiConnectCommand.insertQueueTrack:
          final rawTrack = arguments['track'];
          if (rawTrack is Map) {
            await _insertOrderPositionLocal(
              (arguments['index'] as num?)?.toInt() ?? -1,
              Track.fromJson(Map<String, dynamic>.from(rawTrack)),
            );
          }
        case AriamiConnectCommand.clearQueue:
          _clearUpcomingLocal();
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
      return;
    }

    switch (command) {
      case AriamiConnectCommand.play:
        // just_audio's play() future completes when playback ends, pauses, or
        // stops—not when playback starts. Awaiting it would keep a Connect
        // transfer in "applying" state for the entire first track.
        unawaited(_player.play());
      case AriamiConnectCommand.pause:
        await _player.pause();
      case AriamiConnectCommand.toggle:
        await _togglePlayPauseLocal();
      case AriamiConnectCommand.next:
        await _nextLocal();
      case AriamiConnectCommand.previous:
        await _previousLocal();
      case AriamiConnectCommand.seek:
        await _player.seek(Duration(
          milliseconds: (arguments['positionMs'] as num?)?.toInt() ?? 0,
        ));
      case AriamiConnectCommand.setVolume:
        await _setVolumeLocal(
          (arguments['volume'] as num?)?.toDouble() ?? _volume,
        );
      case AriamiConnectCommand.toggleShuffle:
        _toggleShuffleLocal();
      case AriamiConnectCommand.cycleRepeat:
        _cycleRepeatLocal();
      case AriamiConnectCommand.playQueueIndex:
        await _jumpToOrderPositionLocal(
          (arguments['index'] as num?)?.toInt() ?? -1,
        );
      case AriamiConnectCommand.removeQueueIndex:
        await _removeOrderPositionLocal(
          (arguments['index'] as num?)?.toInt() ?? -1,
          arguments['id'] as String?,
        );
      case AriamiConnectCommand.insertQueueTrack:
        final rawTrack = arguments['track'];
        if (rawTrack is Map) {
          await _insertOrderPositionLocal(
            (arguments['index'] as num?)?.toInt() ?? -1,
            Track.fromJson(Map<String, dynamic>.from(rawTrack)),
          );
        }
      case AriamiConnectCommand.clearQueue:
        _clearUpcomingLocal();
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

  bool get hasNext {
    final remote = _remote;
    if (remote != null) {
      return remote.snapshot.repeatMode != 'off' ||
          remote.snapshot.currentIndex < remote.snapshot.queue.length - 1;
    }
    if (_repeat == PlayerRepeatMode.all || _repeat == PlayerRepeatMode.one) {
      return true;
    }
    return _orderPos >= 0 && _orderPos < _playOrder.length - 1;
  }

  bool get hasPrevious {
    // Previous on the remote device or cast receiver restarts its current track or skips back.
    if (_remote != null || isCastActive) return true;
    return _orderPos > 0 || position.inSeconds > 3;
  }

  List<Track> get upcoming {
    final remote = _remote;
    if (remote != null) {
      final next = remote.snapshot.currentIndex + 1;
      if (next < 1 || next >= _remoteTracks.length) return const <Track>[];
      return _remoteTracks.sublist(next);
    }
    if (_orderPos < 0) return const <Track>[];
    return _playOrder
        .skip(_orderPos + 1)
        .map((i) => _queue[i])
        .toList(growable: false);
  }

  /// A stable identity per [upcoming] row: the underlying queue index behind
  /// each position. Unlike track ids these never repeat, so the queue panel
  /// can use them as reorder keys even when a track is queued twice. Empty
  /// while mirroring a remote device (whose queue can't be edited from here).
  List<int> get upcomingQueueIndices {
    if (_remote != null || _orderPos < 0) return const <int>[];
    return _playOrder.skip(_orderPos + 1).toList(growable: false);
  }

  /// Moves an upcoming track from [oldIndex] to [newIndex], both relative to
  /// the [upcoming] list (0 = the track right after the current one). Only the
  /// play order changes — the queue itself and the current track are left
  /// untouched, so playback keeps going uninterrupted.
  void moveUpcoming(int oldIndex, int newIndex) {
    if (_remote != null || _orderPos < 0) return;
    final base = _orderPos + 1;
    final upcomingLength = _playOrder.length - base;
    if (oldIndex < 0 || oldIndex >= upcomingLength) return;
    // newIndex comes from ReorderableListView's onReorderItem, which already
    // accounts for the item removed at oldIndex — insert at it directly.
    final target = newIndex.clamp(0, upcomingLength - 1);
    if (target == oldIndex) return;
    final entry = _playOrder.removeAt(base + oldIndex);
    _playOrder.insert(base + target, entry);
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  /// Moves several upcoming tracks as one block, landing them at [target] in
  /// the upcoming list that remains once they are lifted out (0 = straight
  /// after the current track). Their relative order is preserved, so a
  /// multi-selection stays in the order the queue showed it.
  void moveUpcomingAll(List<int> upcomingIndices, int target) {
    if (_remote != null || _orderPos < 0) return;
    final base = _orderPos + 1;
    final upcomingLength = _playOrder.length - base;
    final sources = _sortedUpcoming(upcomingIndices, upcomingLength);
    if (sources.isEmpty) return;
    final moved = <int>[for (final i in sources) _playOrder[base + i]];
    for (final i in sources.reversed) {
      _playOrder.removeAt(base + i);
    }
    final landing = target.clamp(0, upcomingLength - moved.length);
    _playOrder.insertAll(base + landing, moved);
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  /// Removes several upcoming tracks at once, leaving the current one playing.
  ///
  /// Removing back-to-front keeps the earlier indices meaningful as the list
  /// shrinks — including on a remote device, where each removal is its own
  /// Connect command against the mirror.
  ///
  /// Returns an undo that puts the tracks back, or null if nothing was removed.
  QueueUndo? removeUpcomingAll(List<int> upcomingIndices) {
    final remote = _remote;
    if (remote != null) {
      final targets = _sortedUpcoming(upcomingIndices, upcoming.length);
      final base = remote.snapshot.currentIndex + 1;
      final undo = _captureRemovalUndo([for (final i in targets) base + i]);
      for (final i in targets.reversed) {
        _removeUpcomingRemote(i);
      }
      return undo;
    }
    if (_orderPos < 0) return null;
    final base = _orderPos + 1;
    final targets = _sortedUpcoming(upcomingIndices, _playOrder.length - base);
    if (targets.isEmpty) return null;
    final undo = _captureRemovalUndo([for (final i in targets) base + i]);
    for (final i in targets.reversed) {
      _playOrder.removeAt(base + i);
    }
    _compactQueueToPlayOrder();
    notifyListeners();
    unawaited(_refreshGaplessTail());
    return undo;
  }

  /// The in-range [upcomingIndices], de-duplicated and in queue order.
  List<int> _sortedUpcoming(List<int> upcomingIndices, int length) =>
      upcomingIndices.where((i) => i >= 0 && i < length).toSet().toList()
        ..sort();

  void attach(PlayerApiClient? client) {
    _client = client;
  }

  /// Every state change schedules a (throttled) save, so the queue, play order,
  /// modes and playback position all survive an app restart.
  @override
  void notifyListeners() {
    super.notifyListeners();
    _scheduleSave();
  }

  final _progress = _ProgressNotifier();

  /// Fires as the playhead moves. Kept apart from the controller's own
  /// notifications so a ticking position only rebuilds the seek bars, not
  /// every widget watching the controller.
  Listenable get progress => _progress;

  /// Listens to every change, position ticks included — for services that
  /// track the playhead (OS media controls, stats, Discord, Connect).
  void addTickingListener(VoidCallback listener) {
    addListener(listener);
    _progress.addListener(listener);
  }

  void removeTickingListener(VoidCallback listener) {
    removeListener(listener);
    _progress.removeListener(listener);
  }

  void _notifyProgress({bool now = false}) {
    _progress.tick(now: now);
    _scheduleSave();
  }

  /// Restores the last session's queue (loaded but paused at the saved
  /// position) so the user doesn't have to re-pick a song on every launch.
  /// Safe to call once after the client is attached; a no-op if a queue is
  /// already loaded or nothing was saved.
  Future<void> restore() async {
    _prefs ??= await SharedPreferences.getInstance();
    final savedQuality = _prefs!.getInt(_qualityPreferenceKey);
    if (savedQuality != null) {
      final restored =
          _enumByIndex(StreamQuality.values, savedQuality, StreamQuality.high);
      if (_qualityPolicy.restorePreferredQuality(restored)) {
        notifyListeners();
      }
    }
    final savedPreferDownloaded =
        _prefs!.getBool(_preferDownloadedPreferenceKey);
    if (savedPreferDownloaded != null &&
        savedPreferDownloaded != _preferDownloadedWhenOnline) {
      _preferDownloadedWhenOnline = savedPreferDownloaded;
      notifyListeners();
    }
    final savedFollowPlayback = _prefs!.getBool(_playButtonsFollowPlaybackKey);
    if (savedFollowPlayback != null &&
        savedFollowPlayback != _playButtonsFollowPlayback) {
      _playButtonsFollowPlayback = savedFollowPlayback;
      notifyListeners();
    }
    final savedKeepQueue = _prefs!.getBool(_keepQueueOnTapKey);
    if (savedKeepQueue != null && savedKeepQueue != _keepQueueOnTap) {
      _keepQueueOnTap = savedKeepQueue;
      notifyListeners();
    }
    final savedStackPlayNext = _prefs!.getBool(_stackPlayNextKey);
    if (savedStackPlayNext != null && savedStackPlayNext != _stackPlayNext) {
      _stackPlayNext = savedStackPlayNext;
      notifyListeners();
    }
    // dart2js stored whole volumes (1.0) as ints; Wasm's getDouble rejects them.
    final savedVolume =
        (_prefs!.get(_volumePreferenceKey) as num?)?.toDouble();
    if (savedVolume != null) {
      final clampedVolume = savedVolume.clamp(0.0, 1.0);
      if (clampedVolume != _volume) {
        _volume = clampedVolume;
        notifyListeners();
      }
      await _player.setVolume(volumeToGain(_volume));
    }

    if (_queue.isNotEmpty) return;
    final raw = _prefs!.getString(_stateKey);
    if (raw == null || raw.isEmpty) return;

    _restoring = true;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final queue = (data['queue'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      if (queue.isEmpty) return;

      _replaceQueue(queue);
      _shuffle = data['shuffle'] as bool? ?? false;
      _sourceId = data['sourceId'] as String?;
      _repeat = _enumByIndex(PlayerRepeatMode.values, data['repeat'] as int?,
          PlayerRepeatMode.off);
      if (savedQuality == null) {
        final legacyQuality = _enumByIndex(
            StreamQuality.values, data['quality'] as int?, StreamQuality.high);
        _qualityPolicy.restorePreferredQuality(legacyQuality);
        await _prefs!.setInt(_qualityPreferenceKey, legacyQuality.index);
      }
      if (savedVolume == null) {
        _volume = ((data['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
        await _prefs!.setDouble(_volumePreferenceKey, _volume);
      }

      // A shorter valid order is a legacy queue edit: keep it and compact the
      // backing queue instead of treating its removed entries as corruption.
      final savedOrder =
          (data['playOrder'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<int>()
              .where((i) => i >= 0 && i < _queue.length)
              .toList();
      final hasUniqueSavedOrder =
          savedOrder.toSet().length == savedOrder.length;
      _playOrder = savedOrder.isNotEmpty && hasUniqueSavedOrder
          ? savedOrder
          : List<int>.generate(_queue.length, (i) => i);
      _orderPos =
          (data['orderPos'] as int? ?? 0).clamp(0, _playOrder.length - 1);
      _compactQueueToPlayOrder();

      final positionMs = data['positionMs'] as int? ?? 0;
      _position = Duration(milliseconds: positionMs < 0 ? 0 : positionMs);

      notifyListeners();
      await _player.setVolume(volumeToGain(_volume));
      // Prepare the track paused at the saved spot; the user presses play.
      await _loadCurrent(autoplay: false, initialPosition: _position);
    } catch (_) {
      // Corrupt or stale state — discard it rather than blocking startup.
      await _prefs!.remove(_stateKey);
    } finally {
      _restoring = false;
    }
  }

  /// Replaces the queue with [tracks] and starts playback at [startIndex].
  ///
  /// Always plays in linear order starting from [startIndex]; the dedicated
  /// shuffle button ([playShuffled]) is the only way to start shuffled, so a
  /// persisted shuffle from a previous session never hijacks the Play button.
  Future<void> playAll(
    List<Track> tracks, {
    int startIndex = 0,
    String? sourceId,
    bool forceRepeatAll = false,
  }) async {
    if (tracks.isEmpty) return;
    _offerQueueReplacementUndo(tracks, sourceId);
    // While another device owns the session, browsing here plays there: send
    // the new queue (in the same rotated order local playback would use) to
    // the active device instead of starting the laptop speakers.
    if (_remote != null) {
      final start = startIndex.clamp(0, tracks.length - 1);
      _sendRemotePlayContext(
        <Track>[
          for (var i = start; i < tracks.length; i++) tracks[i],
          for (var i = 0; i < start; i++) tracks[i],
        ],
        shuffle: false,
        sourceId: sourceId,
        forceRepeatAll: forceRepeatAll,
      );
      return;
    }
    // Playing with no remote session is a takeover; keep stale remote state
    // from flashing back while the hub confirms it.
    _suppressRemoteMirror();
    // Starting a new context is an explicit track change: repeat-one drops to
    // repeat-all, matching skips and the Connect playContext path.
    if (_repeat == PlayerRepeatMode.one) {
      _repeat = PlayerRepeatMode.all;
    }
    if (forceRepeatAll) {
      _repeat = PlayerRepeatMode.all;
    }
    _replaceQueue(tracks);
    _shuffle = false;
    _sourceId = sourceId;
    _buildPlayOrder(startQueueIndex: startIndex.clamp(0, tracks.length - 1));
    _orderPos = 0;
    await _loadCurrent(autoplay: true);
  }

  /// Replaces the queue and immediately starts it in a fresh random order.
  ///
  /// This is intentionally different from toggling shuffle on an existing
  /// queue: album/playlist shuffle buttons should start that collection from a
  /// random track, matching the mobile player.
  Future<void> playShuffled(List<Track> tracks, {String? sourceId}) async {
    if (tracks.isEmpty) return;
    _offerQueueReplacementUndo(tracks, sourceId);
    if (_remote != null) {
      final resolvedOrder = List<int>.generate(tracks.length, (index) => index)
        ..shuffle(Random());
      _sendRemotePlayContext(
        resolvedOrder.map((index) => tracks[index]).toList(growable: false),
        shuffle: true,
        backingOrder: connectBackingOrderFor(resolvedOrder, tracks.length),
        sourceId: sourceId,
      );
      return;
    }
    _suppressRemoteMirror();
    if (_repeat == PlayerRepeatMode.one) {
      _repeat = PlayerRepeatMode.all;
    }
    _replaceQueue(tracks);
    _shuffle = true;
    _sourceId = sourceId;
    _playOrder = List<int>.generate(_queue.length, (i) => i)..shuffle(Random());
    _orderPos = 0;
    await _loadCurrent(autoplay: true);
  }

  /// Plays a single track immediately, replacing the queue — unless
  /// [keepQueueOnTap] is on and tracks are lined up, when only [track] plays
  /// now and the queue carries on after it.
  ///
  /// [sourceId] is the collection the row was clicked in, so starting a track
  /// from inside an album or playlist still marks that collection as playing.
  Future<void> playTrack(
    Track track, {
    List<Track>? context,
    String? sourceId,
  }) async {
    if (_keepQueueOnTap &&
        _queueWorthKeeping(context ?? <Track>[track], sourceId)) {
      return _playNowKeepingQueue(track);
    }
    if (context != null && context.isNotEmpty) {
      final idx = context.indexWhere((t) => t.id == track.id);
      await playAll(context, startIndex: idx < 0 ? 0 : idx, sourceId: sourceId);
    } else {
      await playAll(<Track>[track], sourceId: sourceId);
    }
  }

  /// Plays [track] now and keeps the queue after it, the interrupted track
  /// resuming where it stopped. With nothing playing it simply plays [track].
  /// Returns the play-order position the track landed at (-1 when there was
  /// no queue to keep, so it simply started playing) for undo popups.
  int playNowKeepingQueue(Track track) {
    final remote = _remote;
    final hasQueue = remote != null
        ? remote.snapshot.queue.isNotEmpty
        : _localCurrentTrack != null;
    if (!hasQueue) {
      unawaited(playTrack(track));
      return -1;
    }
    // The track lands at the current position and becomes Now Playing; the
    // interrupted track slides one slot later. The queue mutations inside
    // _playNowKeepingQueue run synchronously, so this position is exact.
    final at = remote != null ? remote.snapshot.currentIndex : _orderPos;
    unawaited(_playNowKeepingQueue(track));
    return at;
  }

  /// Plays only [track] and wraps back to it at the queue boundary.
  Future<void> playSingleRepeated(Track track) =>
      playAll(<Track>[track], forceRepeatAll: true);

  /// Appends [tracks] to the end of the queue. Returns the play-order position
  /// the first track landed at (-1 if [tracks] is empty) so callers can offer
  /// an undo popup that removes exactly what was added.
  int addToQueue(List<Track> tracks) {
    if (tracks.isEmpty) return -1;
    final remote = _remote;
    if (remote != null) return _appendRemoteQueue(remote, tracks);
    final wasEmpty = _queue.isEmpty;
    final startLen = _queue.length;
    final firstPosition = _playOrder.length;
    _queue.addAll(tracks);
    for (var i = 0; i < tracks.length; i++) {
      _playOrder.add(startLen + i);
    }
    if (wasEmpty) {
      _orderPos = 0;
      unawaited(_loadCurrent(autoplay: false));
    }
    notifyListeners();
    unawaited(_refreshGaplessTail());
    return firstPosition;
  }

  /// Inserts tracks to play right after the current one — or, with
  /// [stackPlayNext] on, after the earlier Play next picks still waiting.
  /// Returns the play-order position the first track landed at (-1 if
  /// [tracks] is empty) for undo popups.
  int playNext(List<Track> tracks) {
    if (tracks.isEmpty) return -1;
    final remote = _remote;
    if (remote != null) return _playNextRemote(remote, tracks);
    if (_queue.isEmpty) return addToQueue(tracks);
    // Copies give each pick an identity of its own to find the stack by.
    final picks = [for (final track in tracks) track.copyWith()];
    final at = playNextPosition(
      current: _orderPos,
      length: _playOrder.length,
      stack: _stackPlayNext,
      isTail: (i) => identical(_queue[_playOrder[i]], _playNextTail),
    );
    final startLen = _queue.length;
    _queue.addAll(picks);
    final newIndices = List<int>.generate(picks.length, (i) => startLen + i);
    _playOrder.insertAll(at, newIndices);
    _playNextTail = picks.last;
    notifyListeners();
    unawaited(_refreshGaplessTail());
    return at;
  }

  /// Removes the entry at [position] in play order — the same index space the
  /// Connect `removeQueueIndex` command uses, where the current track sits at
  /// the snapshot's `currentIndex`. Locally, removing the playing track lets
  /// the next one slide into its place. Used to undo queue additions (see
  /// [addToQueue] and [playNext], which return the position they inserted at).
  Future<void> removeQueuePosition(int position) async {
    final remote = _remote;
    if (remote != null) {
      _removeOrderPositionRemote(position);
      return;
    }
    if (position < 0 || position >= _playOrder.length) return;
    await _removeOrderPositionLocal(position, _queue[_playOrder[position]].id);
  }

  Future<void> togglePlayPause() async {
    final remote = _remote;
    if (remote != null) {
      _sendRemote(AriamiConnectCommand.toggle);
      _applyRemoteOptimistic(isPlaying: !remote.snapshot.isPlaying);
      return;
    }
    final cast = _castService;
    if (cast != null && isCastActive) {
      cast.isRemotePlaying ? await pause() : await resume();
      return;
    }
    await _togglePlayPauseLocal();
  }

  Future<void> pause() async {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.pause);
      _applyRemoteOptimistic(isPlaying: false);
      return;
    }
    final cast = _castService;
    if (cast != null && isCastActive) {
      await cast.pause();
      return;
    }
    await pauseLocal();
  }

  Future<void> resume() async {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.play);
      _applyRemoteOptimistic(isPlaying: true);
      return;
    }
    final cast = _castService;
    if (cast != null && isCastActive) {
      await cast.resume();
      return;
    }
    if (_awaitingSourceLoad) {
      _deferPlayToLoad();
      return;
    }
    _invalidateLocalPlayback();
    if (_player.processingState == ProcessingState.completed) {
      await _loadCurrent(autoplay: true);
      return;
    }
    await _playLocalPlayer();
  }

  /// Always pauses this device's own engine, bypassing the remote mirror.
  /// Connect handoffs and takeovers must silence the local player even while
  /// the UI mirrors another device.
  Future<void> pauseLocal() async {
    _invalidateLocalPlayback(suspend: true);
    _autoplayBlocked = false;
    final cast = _castService;
    if (cast != null && isCastActive) {
      await cast.disconnect(stopReceiver: false);
    }
    await _player.pause();
  }

  Future<void> next() async {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.next);
      return;
    }
    _invalidateLocalPlayback();
    await _nextLocal();
  }

  Future<void> previous() async {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.previous);
      return;
    }
    _invalidateLocalPlayback();
    await _previousLocal();
  }

  /// Jumps directly to a track already in the play order (queue view tap).
  Future<void> playFromUpcomingIndex(int upcomingIndex) async {
    final remote = _remote;
    if (remote != null) {
      _sendRemote(AriamiConnectCommand.playQueueIndex, <String, dynamic>{
        'index': remote.snapshot.currentIndex + 1 + upcomingIndex,
      });
      return;
    }
    _invalidateLocalPlayback();
    await _jumpToOrderPositionLocal(_orderPos + 1 + upcomingIndex);
  }

  /// Removes one track from [upcoming] without interrupting the current song.
  ///
  /// [upcomingIndex] is relative to the visible upcoming list, so duplicate
  /// tracks are removed by their exact queue occurrence rather than by id.
  /// When another Connect device is active, the command is sent there and the
  /// local mirror is updated immediately while its authoritative update is in
  /// flight.
  Future<void> removeUpcomingAt(int upcomingIndex) async {
    final remote = _remote;
    if (remote != null) {
      _removeUpcomingRemote(upcomingIndex);
      return;
    }
    if (_orderPos < 0) return;
    final orderPosition = _orderPos + 1 + upcomingIndex;
    if (upcomingIndex < 0 || orderPosition >= _playOrder.length) return;
    final queueIndex = _playOrder[orderPosition];
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    await _removeOrderPositionLocal(
      orderPosition,
      _queue[queueIndex].id,
    );
  }

  Future<void> seek(Duration position) async {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.seek, <String, dynamic>{
        'positionMs': position.inMilliseconds,
      });
      _applyRemoteOptimistic(positionMs: position.inMilliseconds);
      return;
    }
    final cast = _castService;
    if (cast != null && isCastActive) {
      await cast.seek(position);
      return;
    }
    await _player.seek(position);
  }

  Future<void> setVolume(double value) async {
    if (_remote != null) {
      final volume = value.clamp(0.0, 1.0);
      _applyRemoteOptimistic(volume: volume);
      // Sliders fire continuously while dragged; trail the sends.
      _remoteVolumeTimer?.cancel();
      _remoteVolumeTimer = Timer(const Duration(milliseconds: 150), () {
        _sendRemote(AriamiConnectCommand.setVolume, <String, dynamic>{
          'volume': volume,
        });
      });
      return;
    }
    final cast = _castService;
    if (cast != null && isCastActive) {
      await cast.setVolume(value);
      return;
    }
    await _setVolumeLocal(value);
  }

  Future<void> startCastingToDevice(PlayerCastDevice device) async {
    final cast = _castService;
    if (cast == null || isCastActive) return;
    final wasRemote = _remote != null;
    final remoteSnapshot = _remote?.snapshot;
    final track = currentTrack;
    final pos = position;
    final wasPlaying = isPlaying;

    if (wasRemote && remoteSnapshot != null) {
      _sendRemote(AriamiConnectCommand.pause);
      final resolved =
          remoteSnapshot.queue.map(Track.fromJson).toList(growable: false);
      if (resolved.isNotEmpty) {
        _replaceQueue(
            remoteSnapshot.backingOrder.map((index) => resolved[index]));
        _playOrder = List<int>.filled(resolved.length, 0, growable: true);
        for (var i = 0; i < resolved.length; i++) {
          _playOrder[remoteSnapshot.backingOrder[i]] = i;
        }
        _orderPos = remoteSnapshot.currentIndex.clamp(0, resolved.length - 1);
        _shuffle = remoteSnapshot.shuffle;
        _repeat = switch (remoteSnapshot.repeatMode) {
          'all' => PlayerRepeatMode.all,
          'one' => PlayerRepeatMode.one,
          _ => PlayerRepeatMode.off,
        };
        _sourceId = remoteSnapshot.sourceId;
      }
      _suppressRemoteMirror();
    }

    await _player.pause();
    try {
      await cast.connect(device);

      if (track != null && _client != null) {
        final synced = await cast.syncFromPlayback(
          track: track,
          position: pos,
          isPlaying: wasPlaying,
          apiClient: _client!,
          quality: quality,
          force: true,
        );
        if (!synced && wasPlaying) {
          await _loadCurrent(autoplay: true, initialPosition: pos);
        }
      }
    } catch (e) {
      _errorMessage = 'Could not connect to ${device.name}: $e';
      await cast.disconnect();
      if (wasPlaying && track != null) {
        await _loadCurrent(autoplay: true, initialPosition: pos);
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopCastingAndResumeLocal() async {
    final cast = _castService;
    if (cast == null || !isCastActive) return;
    final track = currentTrack;
    final pos = cast.remotePosition;
    final wasPlaying = cast.isRemotePlaying;

    await cast.disconnect();

    if (track != null) {
      await _loadCurrent(autoplay: wasPlaying, initialPosition: pos);
    }
    notifyListeners();
  }

  /// Toggles mute. Muting drops volume to 0 but remembers the prior level so
  /// unmuting (or nudging the slider) restores it. If already at 0, unmutes to
  /// the remembered level (falling back to full volume).
  Future<void> toggleMute() async {
    if (isMuted) {
      final restore = _volumeBeforeMute > 0.0 ? _volumeBeforeMute : 1.0;
      await setVolume(restore);
    } else {
      _volumeBeforeMute = volume;
      await setVolume(0.0);
    }
  }

  void toggleShuffle() {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.toggleShuffle);
      return;
    }
    _toggleShuffleLocal();
  }

  void cycleRepeat() {
    if (_remote != null) {
      _sendRemote(AriamiConnectCommand.cycleRepeat);
      return;
    }
    _cycleRepeatLocal();
  }

  void setQuality(StreamQuality quality) {
    if (!_qualityPolicy.setPreferredQuality(quality)) return;
    unawaited(_persistQualityPreference());
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  void setLocalPlayback(bool value) {
    if (!_qualityPolicy.setLocalPlayback(value)) return;
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  void setPreferDownloadedWhenOnline(bool value) {
    if (_preferDownloadedWhenOnline == value) return;
    _preferDownloadedWhenOnline = value;
    unawaited(() async {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_preferDownloadedPreferenceKey, value);
    }());
    notifyListeners();
    // The change applies from the next resolved source; the queued gapless
    // tail is re-resolved so the upcoming track honours it immediately.
    unawaited(_refreshGaplessTail());
  }

  void setPlayButtonsFollowPlayback(bool value) {
    if (_playButtonsFollowPlayback == value) return;
    _playButtonsFollowPlayback = value;
    unawaited(() async {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_playButtonsFollowPlaybackKey, value);
    }());
    notifyListeners();
  }

  void setKeepQueueOnTap(bool value) {
    if (_keepQueueOnTap == value) return;
    _keepQueueOnTap = value;
    unawaited(() async {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_keepQueueOnTapKey, value);
    }());
    notifyListeners();
  }

  void setStackPlayNext(bool value) {
    if (_stackPlayNext == value) return;
    _stackPlayNext = value;
    unawaited(() async {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_stackPlayNextKey, value);
    }());
    notifyListeners();
  }

  /// Removes the upcoming tracks while leaving the current track (and what's
  /// already been played) untouched, so playback keeps going uninterrupted.
  void clearUpcoming() {
    final remote = _remote;
    if (remote != null) {
      _clearUpcomingRemote(remote);
      return;
    }
    if (_orderPos < 0 || _playOrder.length <= _orderPos + 1) return;
    _playOrder = _playOrder.sublist(0, _orderPos + 1);
    _compactQueueToPlayOrder();
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  /// Reshuffles the upcoming tracks after the current one, keeping playback of
  /// the current track uninterrupted. Sets [shuffle] to true.
  void reshuffleUpcoming() {
    if (_remote != null || _orderPos < 0) return;
    _shuffle = true;
    final base = _orderPos + 1;
    if (base < _playOrder.length) {
      final remaining = _playOrder.sublist(base)..shuffle(Random());
      _playOrder = <int>[
        ..._playOrder.sublist(0, base),
        ...remaining,
      ];
    }
    notifyListeners();
    unawaited(_refreshGaplessTail());
  }

  Future<void> clear() async {
    _loadGeneration++;
    _loadInFlight = false;
    _errorRecoveryTrackId = null;
    _autoplayBlocked = false;
    if (isCastActive) {
      await _castService?.pause();
    }
    await _player.stop();
    _queue.clear();
    _playOrder = <int>[];
    _nativePlaylistOrderPositions = <int>[];
    _activeNativeIndex = null;
    _gaplessTailGeneration++;
    _gaplessTailPending = false;
    _orderPos = -1;
    _sourceId = null;
    _lastSource = null;
    _resumeOrderPosOnReconnect = null;
    _position = Duration.zero;
    _duration = null;
    _isPlaying = false;
    // Drop any saved session too, so a disconnect/logout doesn't restore a
    // stale queue on the next launch.
    _saveTimer?.cancel();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_stateKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _gapless.removeListener(_onGaplessPreferenceChanged);
    _castService?.removeListener(_onCastServiceChanged);
    if (_castService?.onTrackCompleted == _onCastTrackCompleted) {
      _castService?.onTrackCompleted = null;
    }
    _saveTimer?.cancel();
    _remoteTicker?.cancel();
    _remoteVolumeTimer?.cancel();
    _remoteSuppressionTimer?.cancel();
    _unplayableTrackController.close();
    _queueReplacedController.close();
    _progress.dispose();
    // Best-effort final flush so the most recent position survives a clean quit.
    unawaited(_persist());
    _player.dispose();
    super.dispose();
  }
}

/// Coalesces playhead ticks to at most five a second. On Windows and Linux
/// libmpv reports the position dozens of times a second, and each report
/// would otherwise redraw the whole window and wake every playhead service.
class _ProgressNotifier extends ChangeNotifier {
  static const _interval = Duration(milliseconds: 200);

  final _sinceLast = Stopwatch();
  Timer? _pending;

  void tick({bool now = false}) {
    if (now) {
      _pending?.cancel();
      return _fire();
    }
    if (_pending != null) return;
    final wait = _interval - _sinceLast.elapsed;
    if (!_sinceLast.isRunning || wait <= Duration.zero) return _fire();
    _pending = Timer(wait, _fire);
  }

  void _fire() {
    _pending = null;
    _sinceLast
      ..reset()
      ..start();
    notifyListeners();
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }
}
