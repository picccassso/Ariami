import 'package:flutter/foundation.dart';

import '../../utils/shared_preferences_cache.dart';

/// Defines how the search bar behaves when opening the Search tab.
enum SearchMode {
  /// Keyboard does not open automatically; user must tap search manually.
  standard,

  /// Keyboard opens automatically when entering search, mimicking Spotify.
  spotify,
}

extension SearchModeDetails on SearchMode {
  String get label {
    switch (this) {
      case SearchMode.standard:
        return 'Standard';
      case SearchMode.spotify:
        return 'Spotify Mode';
    }
  }

  String get description {
    switch (this) {
      case SearchMode.standard:
        return 'Manual — keyboard will not appear until the search bar is tapped';
      case SearchMode.spotify:
        return 'Automatic — keyboard opens immediately when entering search';
    }
  }
}

/// Persists and publishes the user's search keyboard focus preference
/// and recent searches limit preferences.
class SearchSettingsService extends ChangeNotifier {
  static final SearchSettingsService _instance =
      SearchSettingsService._internal();

  factory SearchSettingsService() => _instance;

  SearchSettingsService._internal();

  static const preferenceKey = 'search_mode';
  static const recentSearchesLimitKey = 'recent_searches_limit';
  static const recentSearchesIsCustomKey = 'recent_searches_is_custom';
  static const recentSongsKey = 'recent_songs';

  static const int standardRecentSearchesLimit = 30;
  static const int minRecentSearchesLimit = 5;
  static const int maxRecentSearchesLimit = 500;

  bool _initialized = false;
  SearchMode _mode = SearchMode.spotify;
  bool _isCustomRecentLimit = false;
  int _customRecentLimit = standardRecentSearchesLimit;

  /// Current search mode. Defaults to [SearchMode.spotify].
  SearchMode get mode => _mode;

  /// Whether the keyboard should automatically open when the Search tab opens.
  bool get isSpotifyMode => _mode == SearchMode.spotify;

  /// Whether a custom limit is active for recent searches.
  bool get isCustomRecentLimit => _isCustomRecentLimit;

  /// The custom limit value configured by the user (clamped to [minRecentSearchesLimit]..[maxRecentSearchesLimit]).
  int get customRecentLimit => _customRecentLimit;

  /// Effective limit for recent searches (30 for standard, or custom number).
  int get recentSearchesLimit =>
      _isCustomRecentLimit ? _customRecentLimit : standardRecentSearchesLimit;

  /// Formatted label for settings display ("Standard (30)" or "Custom (`number`)").
  String get recentSearchesLimitLabel =>
      _isCustomRecentLimit
          ? 'Custom ($_customRecentLimit)'
          : 'Standard ($standardRecentSearchesLimit)';

  /// Initializes the service from pre-loaded [sharedPrefs].
  /// Safe to call multiple times (guarded by [_initialized]).
  void initialize() {
    if (_initialized) return;
    try {
      final raw = sharedPrefs.getString(preferenceKey);
      if (raw == 'standard') {
        _mode = SearchMode.standard;
      } else {
        _mode = SearchMode.spotify;
      }

      _isCustomRecentLimit =
          sharedPrefs.getBool(recentSearchesIsCustomKey) ?? false;
      final savedLimit = sharedPrefs.getInt(recentSearchesLimitKey);
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
      _mode = SearchMode.spotify;
      _isCustomRecentLimit = false;
      _customRecentLimit = standardRecentSearchesLimit;
    }
  }

  /// Updates the search mode preference, notifying listeners
  /// and persisting the value to [sharedPrefs].
  Future<void> setMode(SearchMode mode) async {
    initialize();
    if (_mode == mode) return;

    _mode = mode;
    notifyListeners();
    await sharedPrefs.setString(
      preferenceKey,
      mode == SearchMode.standard ? 'standard' : 'spotify',
    );
  }

  /// Updates the recent searches limit preference, notifying listeners
  /// and persisting the value to [sharedPrefs].
  ///
  /// If the effective limit is reduced below the existing count of recent
  /// searches, immediately trims the stored list in [sharedPrefs].
  Future<void> setRecentSearchesLimit({
    required bool isCustom,
    int? customLimit,
  }) async {
    initialize();
    final clampedCustom = (customLimit ?? _customRecentLimit).clamp(
      minRecentSearchesLimit,
      maxRecentSearchesLimit,
    );
    final changed =
        _isCustomRecentLimit != isCustom || _customRecentLimit != clampedCustom;

    _isCustomRecentLimit = isCustom;
    _customRecentLimit = clampedCustom;

    try {
      await sharedPrefs.setBool(recentSearchesIsCustomKey, _isCustomRecentLimit);
      await sharedPrefs.setInt(recentSearchesLimitKey, _customRecentLimit);

      // Immediately trim stored recent songs if limit was reduced
      final effectiveLimit = recentSearchesLimit;
      final jsonList = sharedPrefs.getStringList(recentSongsKey);
      if (jsonList != null && jsonList.length > effectiveLimit) {
        await sharedPrefs.setStringList(
          recentSongsKey,
          jsonList.sublist(0, effectiveLimit),
        );
      }
    } catch (_) {}

    if (changed) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting({
    SearchMode defaultMode = SearchMode.spotify,
    bool defaultIsCustom = false,
    int defaultCustomLimit = standardRecentSearchesLimit,
  }) {
    _initialized = false;
    _mode = defaultMode;
    _isCustomRecentLimit = defaultIsCustom;
    _customRecentLimit = defaultCustomLimit;
  }
}
