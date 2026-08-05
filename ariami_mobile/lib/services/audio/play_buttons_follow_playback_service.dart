import 'package:flutter/foundation.dart';

import '../../utils/shared_preferences_cache.dart';

/// Persists and publishes the "play button follows playback" preference.
///
/// With it on, an album or playlist that is currently playing shows Pause
/// instead of Play, and its shuffle button toggles the live queue rather than
/// restarting it — matching the desktop app (and Spotify). Opt-in, so by
/// default those buttons always start the collection from the top.
class PlayButtonsFollowPlaybackService extends ChangeNotifier {
  static final PlayButtonsFollowPlaybackService _instance =
      PlayButtonsFollowPlaybackService._internal();

  factory PlayButtonsFollowPlaybackService() => _instance;

  PlayButtonsFollowPlaybackService._internal();

  static const preferenceKey = 'play_buttons_follow_playback';

  bool _initialized = false;
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;

  void initialize() {
    if (_initialized) return;
    _isEnabled = sharedPrefs.getBool(preferenceKey) ?? false;
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
    _isEnabled = false;
  }
}
