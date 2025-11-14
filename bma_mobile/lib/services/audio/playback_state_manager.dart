import 'package:shared_preferences/shared_preferences.dart';

/// Manages playback state persistence across app restarts
class PlaybackStateManager {
  static const String _keyCurrentSongId = 'playback_current_song_id';
  static const String _keyCurrentSongPath = 'playback_current_song_path';
  static const String _keyPosition = 'playback_position';
  static const String _keyIsPlaying = 'playback_is_playing';
  static const String _keyVolume = 'playback_volume';
  static const String _keySpeed = 'playback_speed';

  /// Save current playback state
  Future<void> saveState(PlaybackState state) async {
    final prefs = await SharedPreferences.getInstance();

    if (state.currentSongId != null) {
      await prefs.setString(_keyCurrentSongId, state.currentSongId!);
    } else {
      await prefs.remove(_keyCurrentSongId);
    }

    if (state.currentSongPath != null) {
      await prefs.setString(_keyCurrentSongPath, state.currentSongPath!);
    } else {
      await prefs.remove(_keyCurrentSongPath);
    }

    await prefs.setInt(_keyPosition, state.position.inMilliseconds);
    await prefs.setBool(_keyIsPlaying, state.isPlaying);
    await prefs.setDouble(_keyVolume, state.volume);
    await prefs.setDouble(_keySpeed, state.playbackSpeed);
  }

  /// Load saved playback state
  Future<PlaybackState?> loadState() async {
    final prefs = await SharedPreferences.getInstance();

    final songId = prefs.getString(_keyCurrentSongId);
    final songPath = prefs.getString(_keyCurrentSongPath);

    // If no song was playing, return null
    if (songId == null && songPath == null) {
      return null;
    }

    return PlaybackState(
      currentSongId: songId,
      currentSongPath: songPath,
      position: Duration(milliseconds: prefs.getInt(_keyPosition) ?? 0),
      isPlaying: prefs.getBool(_keyIsPlaying) ?? false,
      volume: prefs.getDouble(_keyVolume) ?? 1.0,
      playbackSpeed: prefs.getDouble(_keySpeed) ?? 1.0,
    );
  }

  /// Clear saved state
  Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentSongId);
    await prefs.remove(_keyCurrentSongPath);
    await prefs.remove(_keyPosition);
    await prefs.remove(_keyIsPlaying);
    await prefs.remove(_keyVolume);
    await prefs.remove(_keySpeed);
  }
}

/// Represents the current playback state
class PlaybackState {
  final String? currentSongId;
  final String? currentSongPath;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isLoading;
  final double volume;
  final double playbackSpeed;

  PlaybackState({
    this.currentSongId,
    this.currentSongPath,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isLoading = false,
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
  });

  /// Create copy with updated fields
  PlaybackState copyWith({
    String? currentSongId,
    String? currentSongPath,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isLoading,
    double? volume,
    double? playbackSpeed,
  }) {
    return PlaybackState(
      currentSongId: currentSongId ?? this.currentSongId,
      currentSongPath: currentSongPath ?? this.currentSongPath,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      volume: volume ?? this.volume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'currentSongId': currentSongId,
      'currentSongPath': currentSongPath,
      'position': position.inMilliseconds,
      'duration': duration.inMilliseconds,
      'isPlaying': isPlaying,
      'isLoading': isLoading,
      'volume': volume,
      'playbackSpeed': playbackSpeed,
    };
  }

  /// Create from JSON
  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      currentSongId: json['currentSongId'] as String?,
      currentSongPath: json['currentSongPath'] as String?,
      position: Duration(milliseconds: json['position'] as int? ?? 0),
      duration: Duration(milliseconds: json['duration'] as int? ?? 0),
      isPlaying: json['isPlaying'] as bool? ?? false,
      isLoading: json['isLoading'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
