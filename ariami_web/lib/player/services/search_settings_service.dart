import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchSettingsService extends ChangeNotifier {
  static final SearchSettingsService _instance =
      SearchSettingsService._internal();

  factory SearchSettingsService() => _instance;

  SearchSettingsService._internal();

  static const String recentSearchesLimitKey = 'recent_searches_limit';
  static const String recentSearchesIsCustomKey = 'recent_searches_is_custom';

  static const int standardRecentSearchesLimit = 30;
  static const int minRecentSearchesLimit = 5;
  static const int maxRecentSearchesLimit = 500;

  bool _initialized = false;
  bool _isCustomRecentLimit = false;
  int _customRecentLimit = standardRecentSearchesLimit;

  bool get isCustomRecentLimit => _isCustomRecentLimit;

  int get customRecentLimit => _customRecentLimit;

  /// Effective limit for recent searches (30 for standard, or custom number).
  int get recentSearchesLimit =>
      _isCustomRecentLimit ? _customRecentLimit : standardRecentSearchesLimit;

  String get recentSearchesLimitLabel => _isCustomRecentLimit
      ? 'Custom ($_customRecentLimit)'
      : 'Standard ($standardRecentSearchesLimit)';

  /// Initializes the service from [SharedPreferences].
  /// Safe to call multiple times (guarded by [_initialized]).
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isCustomRecentLimit =
          prefs.getBool(recentSearchesIsCustomKey) ?? false;
      final savedLimit = prefs.getInt(recentSearchesLimitKey);
      if (savedLimit != null) {
        _customRecentLimit = savedLimit.clamp(
          minRecentSearchesLimit,
          maxRecentSearchesLimit,
        );
      } else {
        _customRecentLimit = standardRecentSearchesLimit;
      }
      _initialized = true;
    } catch (_) {
      _isCustomRecentLimit = false;
      _customRecentLimit = standardRecentSearchesLimit;
    }
  }

  /// Alias for [initialize] to align with other desktop services.
  Future<void> load() => initialize();

  Future<void> setRecentSearchesLimit({
    required bool isCustom,
    int? customLimit,
  }) async {
    await initialize();
    final clampedCustom = (customLimit ?? _customRecentLimit).clamp(
      minRecentSearchesLimit,
      maxRecentSearchesLimit,
    );
    final changed =
        _isCustomRecentLimit != isCustom || _customRecentLimit != clampedCustom;

    _isCustomRecentLimit = isCustom;
    _customRecentLimit = clampedCustom;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(recentSearchesIsCustomKey, _isCustomRecentLimit);
      await prefs.setInt(recentSearchesLimitKey, _customRecentLimit);
    } catch (_) {}

    if (changed) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting({
    bool defaultIsCustom = false,
    int defaultCustomLimit = standardRecentSearchesLimit,
  }) {
    _initialized = false;
    _isCustomRecentLimit = defaultIsCustom;
    _customRecentLimit = defaultCustomLimit;
  }
}
