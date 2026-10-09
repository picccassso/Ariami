import 'package:just_audio/just_audio.dart';
import '../../main.dart' show audioHandler;
import '../../models/song.dart';
import 'audio_handler.dart';

/// Service for managing audio playback
/// Now uses the AudioHandler which provides background playback through a foreground service
///
/// IMPORTANT: This service now wraps the AudioHandler instead of using AudioPlayer directly.
/// The AudioHandler creates a foreground service that keeps the app alive in the background.
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    print('[AudioPlayerService] ========================================');
    print(
        '[AudioPlayerService] Constructor called - creating singleton instance');
    print(
        '[AudioPlayerService] audioHandler at construction time: ${audioHandler == null ? "NULL" : "NOT NULL"}');
    print('[AudioPlayerService] ========================================');
  }

  Future<void> loadSong(
    Song song,
    String streamUrl, {
    Uri? artworkUri,
    GaplessPlaybackItem? upcoming,
  }) async {
    print('[AudioPlayerService] loadSong() called');

    if (audioHandler == null) {
      print(
          '[AudioPlayerService] ERROR: audioHandler is null - AudioService not initialized');
      throw Exception(
          'AudioService not initialized. Background audio is not available.');
    }

    try {
      await audioHandler!.loadSong(
        song,
        streamUrl,
        artworkUri: artworkUri,
        upcoming: upcoming,
      );
    } catch (e) {
      print('[AudioPlayerService] Error loading song: $e');
      rethrow;
    }
  }

  /// Plays audio from a URL; the song metadata feeds the notification.
  Future<void> playSong(
    Song song,
    String streamUrl, {
    Uri? artworkUri,
    GaplessPlaybackItem? upcoming,
  }) async {
    print('[AudioPlayerService] ========================================');
    print('[AudioPlayerService] playSong() called');
    print('[AudioPlayerService] Checking audioHandler status...');
    print(
        '[AudioPlayerService] audioHandler is: ${audioHandler == null ? "NULL" : "NOT NULL"}');
    print(
        '[AudioPlayerService] audioHandler type: ${audioHandler.runtimeType}');
    print(
        '[AudioPlayerService] audioHandler hashCode: ${audioHandler.hashCode}');
    print('[AudioPlayerService] ========================================');

    if (audioHandler == null) {
      print(
          '[AudioPlayerService] ERROR: audioHandler is null - AudioService not initialized');
      throw Exception(
          'AudioService not initialized. Background audio is not available.');
    }

    try {
      print('[AudioPlayerService] playSong() - routing to audioHandler');
      await audioHandler!.playSong(
        song,
        streamUrl,
        artworkUri: artworkUri,
        upcoming: upcoming,
      );
    } catch (e) {
      print('[AudioPlayerService] Error playing song: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    if (audioHandler == null) return;
    await audioHandler?.pause();
  }

  /// Pause local [just_audio] only, without touching a Chromecast session.
  Future<void> pauseLocal() async {
    if (audioHandler == null) return;
    await audioHandler?.pauseLocal();
  }

  Future<void> resume() async {
    if (audioHandler == null) return;
    await audioHandler?.play();
  }

  Future<void> resumeLocal() async => audioHandler?.playLocal();

  Future<void> seekLocal(Duration position) async =>
      audioHandler?.seekLocal(position);

  Future<void> stop() async {
    if (audioHandler == null) return;
    await audioHandler?.stop();
  }

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

  Future<void> setSpeed(double speed) async {
    if (audioHandler == null) return;
    await audioHandler?.setSpeed(speed);
  }

  PlayerState get playerState {
    final handler = audioHandler;
    if (handler == null) {
      return PlayerState(false, ProcessingState.idle);
    }
    return PlayerState(
      handler.isPlaying,
      ProcessingState.ready, // Simplified - handler manages this internally
    );
  }

  Stream<PlayerState> get playerStateStream {
    final handler = audioHandler;
    return handler?.playerStateStream ??
        Stream.value(PlayerState(false, ProcessingState.idle));
  }

  /// Stream of explicit seek requests, including lock-screen controls.
  Stream<Duration> get seekStream {
    final handler = audioHandler;
    return handler?.onSeek ?? const Stream<Duration>.empty();
  }

  Stream<GaplessPlaybackTransition> get gaplessTransitionStream {
    final handler = audioHandler;
    return handler?.onGaplessTransition ??
        const Stream<GaplessPlaybackTransition>.empty();
  }

  Future<void> setUpcomingGaplessItem(
    Song expectedCurrentSong,
    GaplessPlaybackItem? upcoming,
  ) async {
    await audioHandler?.setUpcomingGaplessItem(
      expectedCurrentSong,
      upcoming,
    );
  }

  Stream<Duration> get positionStream {
    final handler = audioHandler;
    return handler?.positionStream ?? Stream.value(Duration.zero);
  }

  Stream<Duration> get bufferedPositionStream {
    final handler = audioHandler;
    return handler?.bufferedPositionStream ?? Stream.value(Duration.zero);
  }

  Stream<Duration?> get durationStream {
    final handler = audioHandler;
    return handler?.durationStream ?? Stream.value(null);
  }

  Duration get position {
    final handler = audioHandler;
    return handler?.position ?? Duration.zero;
  }

  Duration? get duration {
    final handler = audioHandler;
    return handler?.duration;
  }

  Song? get currentSong {
    final handler = audioHandler;
    return handler?.currentSong;
  }

  Duration get bufferedPosition {
    final handler = audioHandler;
    return handler?.bufferedPosition ?? Duration.zero;
  }

  bool get isPlaying {
    final handler = audioHandler;
    return handler?.isPlaying ?? false;
  }

  bool get isLoading {
    final handler = audioHandler;
    return handler?.isLoading ?? false;
  }

  Future<void> dispose() async {
    // AudioHandler is disposed by the audio service, not by this service
    // We don't dispose it here to avoid stopping the foreground service
    print(
        '[AudioPlayerService] Dispose called - AudioHandler managed by AudioService');
  }
}
