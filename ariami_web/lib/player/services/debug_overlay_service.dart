import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the playback debug overlay is shown in the player shell.
/// Off by default: it is a diagnostic tool for advanced users, not everyday UI.
class DebugOverlayService extends ChangeNotifier {
  DebugOverlayService._();

  static final DebugOverlayService instance = DebugOverlayService._();

  static const preferenceKey = 'debug_overlay_enabled_v1';

  bool _enabled = false;

  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(preferenceKey) ?? false;
    } catch (error) {
      debugPrint('[DebugOverlay] Failed to load preference: $error');
      _enabled = false;
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(preferenceKey, enabled);
    } catch (error) {
      debugPrint('[DebugOverlay] Failed to save preference: $error');
    }
  }
}
