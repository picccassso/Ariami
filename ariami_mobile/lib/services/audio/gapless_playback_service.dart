import 'package:flutter/foundation.dart';

import '../../utils/shared_preferences_cache.dart';

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
