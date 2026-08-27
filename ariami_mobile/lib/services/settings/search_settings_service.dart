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

/// Persists and publishes the user's search keyboard focus preference.
class SearchSettingsService extends ChangeNotifier {
  static final SearchSettingsService _instance =
      SearchSettingsService._internal();

  factory SearchSettingsService() => _instance;

  SearchSettingsService._internal();

  static const preferenceKey = 'search_mode';

  bool _initialized = false;
  SearchMode _mode = SearchMode.spotify;

  /// Current search mode. Defaults to [SearchMode.spotify].
  SearchMode get mode => _mode;

  /// Whether the keyboard should automatically open when the Search tab opens.
  bool get isSpotifyMode => _mode == SearchMode.spotify;

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
    } catch (_) {
      _mode = SearchMode.spotify;
    }
    _initialized = true;
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

  @visibleForTesting
  void resetForTesting({SearchMode defaultMode = SearchMode.spotify}) {
    _initialized = false;
    _mode = defaultMode;
  }
}
