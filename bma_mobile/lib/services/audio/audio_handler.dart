import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';

/// AudioHandler implementation for BMA
/// This creates a foreground service that keeps the app alive during music playback
/// and provides media controls in the notification and lock screen.
class BmaAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  // The underlying audio player
  final AudioPlayer _player = AudioPlayer();

  // Current song being played
  Song? _currentSong;

  // Stream controllers for skip events
  final _skipNextController = StreamController<void>.broadcast();
  final _skipPreviousController = StreamController<void>.broadcast();

  // Expose streams for PlaybackManager to listen to
  Stream<void> get onSkipNext => _skipNextController.stream;
  Stream<void> get onSkipPrevious => _skipPreviousController.stream;

  BmaAudioHandler() {
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
        print('[BmaAudioHandler] Player error: $e');
      },
    );

    print('[BmaAudioHandler] Initialized');
  }

  /// Convert Song model to MediaItem for audio_service
  MediaItem _songToMediaItem(Song song, String streamUrl) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album ?? 'Unknown Album',
      duration: song.duration,
      artUri: _getAlbumArtUri(song, streamUrl),
      extras: {
        'filePath': song.filePath,
        'streamUrl': streamUrl,
      },
    );
  }

  /// Get album art URI from stream URL
  /// Constructs the album art URL based on the server URL
  Uri? _getAlbumArtUri(Song song, String streamUrl) {
    if (song.albumId == null) return null;

    try {
      // Extract base URL from stream URL
      // streamUrl format: "http://server:port/api/stream/path/to/file.mp3"
      final uri = Uri.parse(streamUrl);
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';

      // Construct album art URL (use /api/artwork/ endpoint to match server)
      final albumArtUrl = '$baseUrl/api/artwork/${song.albumId}';
      print('[BmaAudioHandler] Album art URL: $albumArtUrl');
      return Uri.parse(albumArtUrl);
    } catch (e) {
      print('[BmaAudioHandler] Error constructing album art URI: $e');
      return null;
    }
  }

  /// Play a song from a stream URL
  Future<void> playSong(Song song, String streamUrl) async {
    print('[BmaAudioHandler] playSong() called');
    print('[BmaAudioHandler] Song: ${song.title} by ${song.artist}');
    print('[BmaAudioHandler] Stream URL: $streamUrl');

    try {
      _currentSong = song;

      // Create MediaItem for the song
      final mediaItem = _songToMediaItem(song, streamUrl);

      // Update the media item in the notification
      this.mediaItem.add(mediaItem);

      // Set the audio source
      await _player.setUrl(streamUrl);

      // Start playback
      await _player.play();

      print('[BmaAudioHandler] Playback started successfully');
    } catch (e, stackTrace) {
      print('[BmaAudioHandler] Error in playSong: $e');
      print('[BmaAudioHandler] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Broadcast the current playback state to the system
  void _broadcastState(PlaybackEvent event) {
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
        androidCompactActionIndices: const [0, 1, 2], // Previous, Play/Pause, Next
        processingState: audioServiceState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0, // Will be updated when we implement queue support
      ),
    );
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
    print('[BmaAudioHandler] play() called');
    await _player.play();
  }

  @override
  Future<void> pause() async {
    print('[BmaAudioHandler] pause() called');
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    print('[BmaAudioHandler] stop() called');
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
    print('[BmaAudioHandler] seek() called: $position');
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    print('[BmaAudioHandler] skipToNext() called - emitting event');
    _skipNextController.add(null);
  }

  @override
  Future<void> skipToPrevious() async {
    print('[BmaAudioHandler] skipToPrevious() called - emitting event');
    _skipPreviousController.add(null);
  }

  @override
  Future<void> setSpeed(double speed) async {
    print('[BmaAudioHandler] setSpeed() called: $speed');
    await _player.setSpeed(speed);
  }

  @override
  Future<void> onTaskRemoved() async {
    print('[BmaAudioHandler] onTaskRemoved() - App swiped away, stopping playback');
    // Stop playback when app is swiped away from recent apps
    await stop();
  }

  // ============================================================================
  // Getters for accessing player state
  // ============================================================================

  /// Check if currently playing
  bool get isPlaying => _player.playing;

  /// Check if loading/buffering
  bool get isLoading =>
      _player.processingState == ProcessingState.loading ||
      _player.processingState == ProcessingState.buffering;

  /// Get current position
  Duration get position => _player.position;

  /// Get current duration
  Duration? get duration => _player.duration;

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
    await _player.dispose();
    await super.stop();
  }
}
