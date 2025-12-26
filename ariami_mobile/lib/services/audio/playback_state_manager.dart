import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/playback_queue.dart';
import '../../models/repeat_mode.dart';
import '../../models/song.dart';

/// Manages playback state persistence across app restarts
class PlaybackStateManager {
  // Legacy keys (kept for backward compatibility)
  static const String _keyCurrentSongId = 'playback_current_song_id';
  static const String _keyCurrentSongPath = 'playback_current_song_path';
  static const String _keyPosition = 'playback_position';
  static const String _keyIsPlaying = 'playback_is_playing';
  static const String _keyVolume = 'playback_volume';
  static const String _keySpeed = 'playback_speed';

  // New complete state keys
  static const String _keyQueue = 'playback_queue';
  static const String _keyShuffle = 'playback_shuffle';
  static const String _keyRepeat = 'playback_repeat';
  static const String _keyOriginalQueue = 'playback_original_queue';
  static const String _keyStateVersion = 'playback_state_version';
  static const int _currentVersion = 1;

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

  /// Save complete playback state (queue, shuffle, repeat, position)
  Future<void> saveCompletePlaybackState({
    required PlaybackQueue queue,
    required bool isShuffleEnabled,
    required RepeatMode repeatMode,
    required Duration position,
    List<Song>? originalQueue,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save version
      await prefs.setInt(_keyStateVersion, _currentVersion);

      // Save queue as JSON
      if (queue.isNotEmpty) {
        final queueJson = jsonEncode(queue.toJson());
        await prefs.setString(_keyQueue, queueJson);
      } else {
        await prefs.remove(_keyQueue);
      }

      // Save shuffle state
      await prefs.setBool(_keyShuffle, isShuffleEnabled);

      // Save repeat mode
      await prefs.setString(_keyRepeat, repeatMode.toStorageString());

      // Save position
      await prefs.setInt(_keyPosition, position.inMilliseconds);

      // Save original queue if shuffled
      if (originalQueue != null && originalQueue.isNotEmpty && isShuffleEnabled) {
        final originalQueueJson = jsonEncode(
          originalQueue.map((song) => song.toJson()).toList(),
        );
        await prefs.setString(_keyOriginalQueue, originalQueueJson);
      } else {
        await prefs.remove(_keyOriginalQueue);
      }
    } catch (e) {
      print('[PlaybackStateManager] Error saving complete state: $e');
    }
  }

  /// Load complete playback state
  Future<CompletePlaybackState?> loadCompletePlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check version (for future migrations)
      final version = prefs.getInt(_keyStateVersion);
      if (version == null) {
        // No saved state
        return null;
      }

      // Load queue
      final queueJsonString = prefs.getString(_keyQueue);
      if (queueJsonString == null) {
        // No queue saved
        return null;
      }

      final queueJson = jsonDecode(queueJsonString) as Map<String, dynamic>;
      final queue = PlaybackQueue.fromJson(queueJson);

      // If queue is empty, return null
      if (queue.isEmpty) {
        return null;
      }

      // Load shuffle state
      final isShuffleEnabled = prefs.getBool(_keyShuffle) ?? false;

      // Load repeat mode
      final repeatModeString = prefs.getString(_keyRepeat) ?? 'none';
      final repeatMode = RepeatMode.fromStorageString(repeatModeString);

      // Load position
      final positionMs = prefs.getInt(_keyPosition) ?? 0;
      final position = Duration(milliseconds: positionMs);

      // Load original queue if it exists
      List<Song>? originalQueue;
      final originalQueueJsonString = prefs.getString(_keyOriginalQueue);
      if (originalQueueJsonString != null) {
        final originalQueueJson =
            jsonDecode(originalQueueJsonString) as List<dynamic>;
        originalQueue = originalQueueJson
            .map((songJson) => Song.fromJson(songJson as Map<String, dynamic>))
            .toList();
      }

      return CompletePlaybackState(
        queue: queue,
        isShuffleEnabled: isShuffleEnabled,
        repeatMode: repeatMode,
        position: position,
        originalQueue: originalQueue,
      );
    } catch (e) {
      print('[PlaybackStateManager] Error loading complete state: $e');
      // Clear corrupted state
      await clearCompletePlaybackState();
      return null;
    }
  }

  /// Clear all complete playback state
  Future<void> clearCompletePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStateVersion);
    await prefs.remove(_keyQueue);
    await prefs.remove(_keyShuffle);
    await prefs.remove(_keyRepeat);
    await prefs.remove(_keyPosition);
    await prefs.remove(_keyOriginalQueue);
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

/// Represents complete playback state including queue, shuffle, and repeat
class CompletePlaybackState {
  final PlaybackQueue queue;
  final bool isShuffleEnabled;
  final RepeatMode repeatMode;
  final Duration position;
  final List<Song>? originalQueue;

  CompletePlaybackState({
    required this.queue,
    required this.isShuffleEnabled,
    required this.repeatMode,
    required this.position,
    this.originalQueue,
  });
}
