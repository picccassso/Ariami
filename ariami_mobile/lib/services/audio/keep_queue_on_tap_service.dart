import 'package:flutter/foundation.dart';

import '../../utils/shared_preferences_cache.dart';

/// Persists and publishes "Keep My Queue When Tapping a Song": with it on, a
/// tapped song plays now and the queue carries on after it (the interrupted
/// song resuming where it stopped) instead of being replaced. Play and
/// Shuffle buttons still replace the queue.
class KeepQueueOnTapService extends ChangeNotifier {
  static final KeepQueueOnTapService _instance =
      KeepQueueOnTapService._internal();

  factory KeepQueueOnTapService() => _instance;

  KeepQueueOnTapService._internal();

  static const preferenceKey = 'keep_queue_on_tap';

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
}
