import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Buffered headroom the active stream must have before the next track's
/// source is prepared (matches mobile's speculative gapless threshold).
const Duration speculativeGaplessHeadroom = Duration(seconds: 20);

/// Whether the active stream has enough buffered audio to prepare another
/// network source without endangering uninterrupted playback.
///
/// A track buffered to its full [duration] always qualifies: its download is
/// finished, so preparing the next source cannot compete with it — and near
/// the end of a song (when gapless matters most) the remaining headroom is
/// necessarily below any fixed threshold. File-backed sources buffer to full
/// duration almost immediately, so local playback is effectively ungated.
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

class GaplessPlaybackService extends ChangeNotifier {
  static final GaplessPlaybackService _instance =
      GaplessPlaybackService._internal();

  factory GaplessPlaybackService() => _instance;

  GaplessPlaybackService._internal();

  static const preferenceKey = 'gapless_playback_enabled';

  bool _initialized = false;
  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(preferenceKey) ?? true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    await initialize();
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceKey, enabled);
  }

  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _isEnabled = true;
  }
}
