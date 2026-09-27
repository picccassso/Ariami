import 'package:flutter/foundation.dart';

import '../../utils/shared_preferences_cache.dart';

/// Persists and publishes "Stack Play Next": with it on, Play Next goes after
/// the earlier Play Next picks still waiting instead of straight after the
/// current song, so picks play in the order they were chosen.
class StackPlayNextService extends ChangeNotifier {
  static final StackPlayNextService _instance =
      StackPlayNextService._internal();

  factory StackPlayNextService() => _instance;

  StackPlayNextService._internal();

  static const preferenceKey = 'stack_play_next';

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
