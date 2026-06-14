import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import '../cast/chrome_cast_service.dart';

/// AudioHandler implementation for Ariami
/// This creates a foreground service that keeps the app alive during music playback
/// and provides media controls in the notification and lock screen.
class AriamiAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  // The underlying audio player
  final AudioPlayer _player = AudioPlayer();

  // Current song being played
  Song? _currentSong;

  // Stream controllers for skip events
  final _skipNextController = StreamController<void>.broadcast();
  final _skipPreviousController = StreamController<void>.broadcast();
  final _seekController = StreamController<Duration>.broadcast();
  final ChromeCastService _castService = ChromeCastService();

  bool _isCastMode = false;

  // Expose streams for PlaybackManager to listen to
  Stream<void> get onSkipNext => _skipNextController.stream;
  Stream<void> get onSkipPrevious => _skipPreviousController.stream;
  Stream<Duration> get onSeek => _seekController.stream;

  AriamiAudioHandler() {
    _init();
  }

  /// Initialize the audio handler
  void _init() {
    // Listen to player state changes and broadcast to the system
    _player.playbackEventStream.listen(_broadcastState);

    // Listen to processing state changes
    _player.processingStateStream.listen((state) {
      // When song completes, notify listeners
      if (state == ProcessingState.completed) {
        // Broadcast completion through the audio service
        _broadcastState(_player.playbackEvent);
      }
    });

    // Listen to player errors
    _player.playerStateStream.listen(
      (state) {},
      onError: (Object e, StackTrace st) {
        print('[AriamiAudioHandler] Player error: $e');
      },
    );

    print('[AriamiAudioHandler] Initialized');
  }

  /// Convert Song model to MediaItem for audio_service
  MediaItem _songToMediaItem(Song song, String streamUrl, {Uri? artworkUri}) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album ?? 'Unknown Album',
      duration: song.duration,
      artUri: artworkUri ?? _getAlbumArtUri(song, streamUrl),
      extras: {
        'filePath': song.filePath,
        'streamUrl': streamUrl,
      },
    );
  }

  /// Get album art URI from stream URL
  /// Constructs the album art URL based on the server URL
  Uri? _getAlbumArtUri(Song song, String streamUrl) {
    try {
      // Extract base URL from stream URL
      // streamUrl format: "http://server:port/api/stream/path/to/file.mp3"
      final uri = Uri.parse(streamUrl);

      // Guard: Only construct artwork URL for http/https streams
      // file:// URLs (local/cached playback) don't have valid host:port
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        print(
            '[AriamiAudioHandler] Cannot construct artwork URL for non-http stream: ${uri.scheme}');
        return null;
      }

      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';

      // Construct artwork URL based on whether song has albumId
      String artworkUrl;
      if (song.albumId != null) {
        // Song belongs to an album - use album artwork endpoint
        artworkUrl = '$baseUrl/api/artwork/${song.albumId}';
      } else {
        // Standalone song - use song artwork endpoint
        artworkUrl = '$baseUrl/api/song-artwork/${song.id}';
      }

      var artworkUri = Uri.parse(artworkUrl);

      // If stream URL carries streamToken, reuse it for artwork access.
      final streamToken = uri.queryParameters['streamToken'];
      if (streamToken != null && streamToken.isNotEmpty) {
        artworkUri = artworkUri.replace(
          queryParameters: {'streamToken': streamToken},
        );
      }

      print('[AriamiAudioHandler] Album art URL: $artworkUri');
      return artworkUri;
    } catch (e) {
      print('[AriamiAudioHandler] Error constructing album art URI: $e');
      return null;
    }
  }

  /// Pause local playback only. Used when handing off to Chromecast so the
  /// remote session is not affected by cast-mode control delegation.
  Future<void> pauseLocal() async {
    await _player.pause();
  }

  /// Load a song without starting playback (for seeking before play)
  Future<void> loadSong(Song song, String streamUrl, {Uri? artworkUri}) async {
    print('[AriamiAudioHandler] loadSong() called');
    print('[AriamiAudioHandler] Song: ${song.title} by ${song.artist}');
    print('[AriamiAudioHandler] Stream URL: $streamUrl');
    print('[AriamiAudioHandler] Artwork URI: $artworkUri');

    try {
      _currentSong = song;

      // Create MediaItem for the song
      final mediaItem =
          _songToMediaItem(song, streamUrl, artworkUri: artworkUri);

      // Update the media item in the notification
      this.mediaItem.add(mediaItem);

      // Set the audio source WITHOUT starting playback
      await _player.setUrl(streamUrl);

      print('[AriamiAudioHandler] Song loaded successfully (not playing)');
    } catch (e, stackTrace) {
      print('[AriamiAudioHandler] Error in loadSong: $e');
      print('[AriamiAudioHandler] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Play a song from a stream URL
  Future<void> playSong(Song song, String streamUrl, {Uri? artworkUri}) async {
    print('[AriamiAudioHandler] playSong() called');
    print('[AriamiAudioHandler] Song: ${song.title} by ${song.artist}');
    print('[AriamiAudioHandler] Stream URL: $streamUrl');
    print('[AriamiAudioHandler] Artwork URI: $artworkUri');

    try {
      // Load the song first
      await loadSong(song, streamUrl, artworkUri: artworkUri);

      // Start playback (don't await - let it complete asynchronously)
      // The play() Future may not complete immediately, but playback will start
      // and state changes are tracked through stream listeners
      _player.play();

      print('[AriamiAudioHandler] Playback started successfully');
    } catch (e, stackTrace) {
      print('[AriamiAudioHandler] Error in playSong: $e');
      print('[AriamiAudioHandler] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Broadcast the current playback state to the system
  void _broadcastState(PlaybackEvent event) {
    if (_isCastMode) {
      return;
    }

    final playing = _player.playing;
    final processingState = _player.processingState;

    // Map just_audio processing state to audio_service state
    final audioServiceState = _mapProcessingState(processingState, playing);

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [
          0,
          1,
          2
        ], // Previous, Play/Pause, Next
        processingState: audioServiceState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0, // Will be updated when we implement queue support
      ),
    );
  }

  void _broadcastCastState({
    required Duration position,
    required bool isPlaying,
    Duration? duration,
    required bool isBuffering,
  }) {
    final processingState = isBuffering
        ? AudioProcessingState.buffering
        : AudioProcessingState.ready;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1.0,
        queueIndex: 0,
      ),
    );
  }

  /// Switch notification to cast playback without starting local audio.
  void enterCastMode(
    Song song,
    String streamUrl,
    Uri? artworkUri,
    Duration position,
    bool isPlaying,
  ) {
    print(
      '[AriamiAudioHandler] enterCastMode: ${song.title} at ${position.inMilliseconds}ms',
    );
    _isCastMode = true;
    _currentSong = song;
    mediaItem.add(_songToMediaItem(song, streamUrl, artworkUri: artworkUri));
    _broadcastCastState(
      position: position,
      isPlaying: isPlaying,
      duration: song.duration,
      isBuffering: false,
    );
  }

  /// Keep the Ariami notification in sync with remote cast playback.
  void updateCastPlaybackState({
    required Duration position,
    required bool isPlaying,
    Duration? duration,
    required bool isBuffering,
  }) {
    if (!_isCastMode) {
      return;
    }
    _broadcastCastState(
      position: position,
      isPlaying: isPlaying,
      duration: duration,
      isBuffering: isBuffering,
    );
  }

  /// Restore local notification control from just_audio state.
  void exitCastMode() {
    if (!_isCastMode) {
      return;
    }
    print('[AriamiAudioHandler] exitCastMode');
    _isCastMode = false;
    _broadcastState(_player.playbackEvent);
  }

  /// Map just_audio ProcessingState to audio_service AudioProcessingState
  AudioProcessingState _mapProcessingState(
    ProcessingState processingState,
    bool playing,
  ) {
    switch (processingState) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  // ============================================================================
  // MediaHandler overrides - Handle media button events
  // ============================================================================

  @override
  Future<void> play() async {
    print('[AriamiAudioHandler] play() called');
    if (_isCastMode) {
      await _castService.play();
      updateCastPlaybackState(
        position: _castService.remotePosition,
        isPlaying: true,
        duration: _castService.remoteDuration ?? _currentSong?.duration,
        isBuffering: _castService.isRemoteBuffering,
      );
      return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    print('[AriamiAudioHandler] pause() called');
    if (_isCastMode) {
      await _castService.pause();
      updateCastPlaybackState(
        position: _castService.remotePosition,
        isPlaying: false,
        duration: _castService.remoteDuration ?? _currentSong?.duration,
        isBuffering: false,
      );
      return;
    }
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    print('[AriamiAudioHandler] stop() called');
    if (_isCastMode) {
      _isCastMode = false;
    }
    await _player.stop();
    await _player.seek(Duration.zero);

    // Clear the current media item
    mediaItem.add(null);
    _currentSong = null;

    // Update state to stopped
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));

    // This will remove the notification
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    print('[AriamiAudioHandler] seek() called: $position');
    _seekController.add(position);
    if (_isCastMode) {
      await _castService.seek(
        position,
        playAfterSeek: _castService.isRemotePlaying,
      );
      updateCastPlaybackState(
        position: position,
        isPlaying: _castService.isRemotePlaying,
        duration: _castService.remoteDuration ?? _currentSong?.duration,
        isBuffering: _castService.isRemoteBuffering,
      );
      return;
    }
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    print('[AriamiAudioHandler] skipToNext() called - emitting event');
    _skipNextController.add(null);
  }

  @override
  Future<void> skipToPrevious() async {
    print('[AriamiAudioHandler] skipToPrevious() called - emitting event');
    _skipPreviousController.add(null);
  }

  @override
  Future<void> setSpeed(double speed) async {
    print('[AriamiAudioHandler] setSpeed() called: $speed');
    await _player.setSpeed(speed);
  }

  @override
  Future<void> onTaskRemoved() async {
    print(
        '[AriamiAudioHandler] onTaskRemoved() - App swiped away, stopping playback');
    try {
      await _castService.stopForAppTermination(reason: 'task-removed');
    } catch (e) {
      debugPrint(
        '[AriamiAudioHandler] Failed to stop Chromecast during task removal: $e',
      );
    }
    // Stop playback when app is swiped away from recent apps
    await stop();
  }

  // ============================================================================
  // Getters for accessing player state
  // ============================================================================

  /// Check if currently playing
  bool get isPlaying =>
      _isCastMode ? _castService.isRemotePlaying : _player.playing;

  /// Check if loading/buffering
  bool get isLoading => _isCastMode
      ? _castService.isRemoteBuffering
      : _player.processingState == ProcessingState.loading ||
          _player.processingState == ProcessingState.buffering;

  /// Get current position
  Duration get position =>
      _isCastMode ? _castService.remotePosition : _player.position;

  /// Get current duration
  Duration? get duration => _isCastMode
      ? (_castService.remoteDuration ?? _currentSong?.duration)
      : _player.duration;

  /// Get buffered position
  Duration get bufferedPosition => _player.bufferedPosition;

  /// Get current song
  Song? get currentSong => _currentSong;

  /// Stream of player states
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Stream of positions
  Stream<Duration> get positionStream => _player.positionStream;

  /// Stream of durations
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Stream of buffered positions
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose the audio handler and player
  Future<void> dispose() async {
    await _skipNextController.close();
    await _skipPreviousController.close();
    await _seekController.close();
    await _player.dispose();
    await super.stop();
  }
}
