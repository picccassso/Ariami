import 'package:flutter/foundation.dart';

import '../../utils/shared_preferences_cache.dart';

const Duration speculativeGaplessHeadroom = Duration(seconds: 20);

/// Whether the active stream has enough buffered audio to prepare another
/// network source without endangering uninterrupted playback.
///
/// A track buffered to its full [duration] always qualifies: its download is
/// finished, so preparing the next source cannot compete with it — and near
/// the end of a song (when gapless matters most) the remaining headroom is
/// necessarily below any fixed threshold.
bool hasSpeculativeGaplessHeadroom({
  required Duration position,
  required Duration bufferedPosition,
  Duration? duration,
  Duration requiredHeadroom = speculativeGaplessHeadroom,
}) {
  if (duration != null &&
      duration > Duration.zero &&
      bufferedPosition >= duration) {
    return true;
  }
  return bufferedPosition - position >= requiredHeadroom;
}

/// Persists and publishes the user's gapless-playback preference.
class GaplessPlaybackService extends ChangeNotifier {
  static final GaplessPlaybackService _instance =
      GaplessPlaybackService._internal();

  factory GaplessPlaybackService() => _instance;

  GaplessPlaybackService._internal();

  static const preferenceKey = 'gapless_playback_enabled';

  bool _initialized = false;
  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  void initialize() {
    if (_initialized) return;
    _isEnabled = sharedPrefs.getBool(preferenceKey) ?? true;
    _initialized = true;
  }

  Future<void> setEnabled(bool enabled) async {
    initialize();
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    notifyListeners();
    await sharedPrefs.setBool(preferenceKey, enabled);
  }

  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _isEnabled = true;
  }
}
