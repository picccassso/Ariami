import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether account and license details are shown in Settings.
/// Hidden by default so screen recordings don't leak personal info.
class SensitiveInfoService extends ChangeNotifier {
  SensitiveInfoService._();

  static final SensitiveInfoService instance = SensitiveInfoService._();

  static const preferenceKey = 'show_sensitive_info_v1';
  static const hintSeenKey = 'sensitive_info_hint_seen_v1';
  static const mask = '••••••••';

  bool _visible = false;
  bool _hintSeen = false;

  bool get visible => _visible;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _visible = prefs.getBool(preferenceKey) ?? false;
      _hintSeen = prefs.getBool(hintSeenKey) ?? false;
    } catch (error) {
      debugPrint('[SensitiveInfo] Failed to load preference: $error');
      _visible = false;
    }
    notifyListeners();
  }

  Future<void> setVisible(bool visible) async {
    if (_visible == visible) return;
    _visible = visible;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(preferenceKey, visible);
    } catch (error) {
      debugPrint('[SensitiveInfo] Failed to save preference: $error');
    }
  }

  /// True only the first time it is called ever: whether to show the
  /// "you can always show these in General settings" hint.
  Future<bool> consumeFirstRevealHint() async {
    if (_hintSeen) return false;
    _hintSeen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(hintSeenKey, true);
    } catch (error) {
      debugPrint('[SensitiveInfo] Failed to save hint flag: $error');
    }
    return true;
  }
}
