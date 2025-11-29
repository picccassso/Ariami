import 'package:just_audio/just_audio.dart';
import '../../main.dart' show audioHandler;
import '../../models/song.dart';

/// Service for managing audio playback
/// Now uses the AudioHandler which provides background playback through a foreground service
///
/// IMPORTANT: This service now wraps the AudioHandler instead of using AudioPlayer directly.
/// The AudioHandler creates a foreground service that keeps the app alive in the background.
class AudioPlayerService {
  // Singleton pattern
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    print('[AudioPlayerService] ========================================');
    print('[AudioPlayerService] Constructor called - creating singleton instance');
    print('[AudioPlayerService] audioHandler at construction time: ${audioHandler == null ? "NULL" : "NOT NULL"}');
    print('[AudioPlayerService] ========================================');
  }

  /// Load a song without starting playback (for seeking before play)
  Future<void> loadSong(Song song, String streamUrl) async {
    print('[AudioPlayerService] loadSong() called');

    // Check if audioHandler is initialized
    if (audioHandler == null) {
      print('[AudioPlayerService] ERROR: audioHandler is null - AudioService not initialized');
      throw Exception('AudioService not initialized. Background audio is not available.');
    }

    try {
      await audioHandler!.loadSong(song, streamUrl);
    } catch (e) {
      print('[AudioPlayerService] Error loading song: $e');
      rethrow;
    }
  }

  /// Play audio from URL with song metadata
  /// This is the NEW method that should be used - it provides metadata for the notification
  Future<void> playSong(Song song, String streamUrl) async {
    print('[AudioPlayerService] ========================================');
    print('[AudioPlayerService] playSong() called');
    print('[AudioPlayerService] Checking audioHandler status...');
    print('[AudioPlayerService] audioHandler is: ${audioHandler == null ? "NULL" : "NOT NULL"}');
    print('[AudioPlayerService] audioHandler type: ${audioHandler.runtimeType}');
    print('[AudioPlayerService] audioHandler hashCode: ${audioHandler.hashCode}');
    print('[AudioPlayerService] ========================================');

    // Check if audioHandler is initialized
    if (audioHandler == null) {
      print('[AudioPlayerService] ERROR: audioHandler is null - AudioService not initialized');
      throw Exception('AudioService not initialized. Background audio is not available.');
    }

    try {
      print('[AudioPlayerService] playSong() - routing to audioHandler');
      await audioHandler!.playSong(song, streamUrl);
    } catch (e) {
      print('[AudioPlayerService] Error playing song: $e');
      rethrow;
    }
  }

  /// Play audio from URL (legacy method for backwards compatibility)
  /// NOTE: This method is deprecated - use playSong() instead to get proper notifications
  @Deprecated('Use playSong() instead to provide song metadata for notifications')
  Future<void> play(String streamUrl) async {
    try {
      print('[AudioPlayerService] WARNING: play() called without song metadata');
      print('[AudioPlayerService] Notification will not show proper song info');
      // We can't call audioHandler.playSong() without a Song object
      // This is intentionally left unimplemented to force migration to playSong()
      throw UnimplementedError(
        'play() is deprecated. Use playSong() with Song metadata instead.',
      );
    } catch (e) {
      print('[AudioPlayerService] Error: $e');
      rethrow;
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (audioHandler == null) return;
    await audioHandler?.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    if (audioHandler == null) return;
    await audioHandler?.play();
  }

  /// Stop playback
  Future<void> stop() async {
    if (audioHandler == null) return;
    await audioHandler?.stop();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (audioHandler == null) return;
    await audioHandler?.seek(position);
  }

  /// Set volume (0.0 to 1.0)
  /// Note: Volume control is handled by the system for background audio
  Future<void> setVolume(double volume) async {
    // Volume is managed by the system media session
    // Individual app volume control is not recommended for background audio
    print('[AudioPlayerService] Volume control through system media controls');
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    if (audioHandler == null) return;
    await audioHandler?.setSpeed(speed);
  }

  /// Get current playback state
  PlayerState get playerState {
    final handler = audioHandler;
    if (handler == null) {
      return PlayerState(false, ProcessingState.idle);
    }
    // Return a PlayerState based on audioHandler's state
    return PlayerState(
      handler.isPlaying,
      ProcessingState.ready, // Simplified - handler manages this internally
    );
  }

  /// Stream of player states
  Stream<PlayerState> get playerStateStream {
    final handler = audioHandler;
    return handler?.playerStateStream ?? Stream.value(PlayerState(false, ProcessingState.idle));
  }

  /// Stream of playback positions
  Stream<Duration> get positionStream {
    final handler = audioHandler;
    return handler?.positionStream ?? Stream.value(Duration.zero);
  }

  /// Stream of buffered positions
  Stream<Duration> get bufferedPositionStream {
    final handler = audioHandler;
    return handler?.bufferedPositionStream ?? Stream.value(Duration.zero);
  }

  /// Stream of durations
  Stream<Duration?> get durationStream {
    final handler = audioHandler;
    return handler?.durationStream ?? Stream.value(null);
  }

  /// Get current position
  Duration get position {
    final handler = audioHandler;
    return handler?.position ?? Duration.zero;
  }

  /// Get current duration
  Duration? get duration {
    final handler = audioHandler;
    return handler?.duration;
  }

  /// Get buffered position
  Duration get bufferedPosition {
    final handler = audioHandler;
    return handler?.bufferedPosition ?? Duration.zero;
  }

  /// Check if playing
  bool get isPlaying {
    final handler = audioHandler;
    return handler?.isPlaying ?? false;
  }

  /// Check if loading
  bool get isLoading {
    final handler = audioHandler;
    return handler?.isLoading ?? false;
  }

  /// Get the underlying audio player instance (for backwards compatibility)
  /// WARNING: Direct access to the player bypasses the foreground service!
  @Deprecated('Direct player access bypasses foreground service - use service methods instead')
  AudioPlayer? get player => null; // Intentionally return null to prevent direct access

  /// Dispose the player
  Future<void> dispose() async {
    // AudioHandler is disposed by the audio service, not by this service
    // We don't dispose it here to avoid stopping the foreground service
    print('[AudioPlayerService] Dispose called - AudioHandler managed by AudioService');
  }
}
