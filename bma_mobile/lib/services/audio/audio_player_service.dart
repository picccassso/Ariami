import 'package:just_audio/just_audio.dart';

/// Service for managing audio playback
/// Uses just_audio package for streaming from server
class AudioPlayerService {
  // Singleton pattern
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _player = AudioPlayer();

  /// Get the underlying audio player instance
  AudioPlayer get player => _player;

  /// Play audio from URL
  Future<void> play(String streamUrl) async {
    try {
      // Set the audio source
      await _player.setUrl(streamUrl);
      // Start playback
      await _player.play();
    } catch (e) {
      print('Error playing audio: $e');
      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    await _player.play();
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  /// Get current playback state
  PlayerState get playerState => _player.playerState;

  /// Stream of player states
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Stream of playback positions
  Stream<Duration> get positionStream => _player.positionStream;

  /// Stream of buffered positions
  Stream<Duration> get bufferedPositionStream =>
      _player.bufferedPositionStream;

  /// Stream of durations
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Get current position
  Duration get position => _player.position;

  /// Get current duration
  Duration? get duration => _player.duration;

  /// Get buffered position
  Duration get bufferedPosition => _player.bufferedPosition;

  /// Check if playing
  bool get isPlaying => _player.playing;

  /// Check if loading
  bool get isLoading => _player.processingState == ProcessingState.loading ||
      _player.processingState == ProcessingState.buffering;

  /// Dispose the player
  Future<void> dispose() async {
    await _player.dispose();
  }
}
