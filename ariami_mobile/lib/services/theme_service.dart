import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // For sharedPrefs
import '../utils/constants.dart';
import 'color_extraction_service.dart';
import 'playback_manager.dart';

enum ThemeSource {
  preset,
  custom,
  dynamicCoverArt,
  staticCoverArt,
}

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _themeModeKey = 'theme_mode';
  static const String _themeSourceKey = 'theme_source';
  static const String _presetColorKey = 'theme_preset_color';
  static const String _customColorKey = 'theme_custom_color';
  static const String _staticCoverArtColorKey = 'theme_static_cover_art_color';

  final ColorExtractionService _colorService = ColorExtractionService();
  final PlaybackManager _playbackManager = PlaybackManager();

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeSource _themeSource = ThemeSource.preset;

  Color _presetColor = const Color(0xFFFFFFFF); // Default pure white
  Color _customColor = const Color(0xFFFFFFFF);
  Color _staticCoverArtColor = const Color(0xFFFFFFFF);

  ThemeMode get themeMode => _themeMode;
  ThemeSource get themeSource => _themeSource;
  Color get presetColor => _presetColor;
  Color get customColor => _customColor;
  Color get staticCoverArtColor => _staticCoverArtColor;

  Color get currentSeedColor {
    switch (_themeSource) {
      case ThemeSource.preset:
        return _presetColor;
      case ThemeSource.custom:
        return _customColor;
      case ThemeSource.staticCoverArt:
        return _staticCoverArtColor;
      case ThemeSource.dynamicCoverArt:
        return _colorService.currentColors.primary;
    }
  }

  ThemeData get lightTheme => AppTheme.buildTheme(
        brightness: Brightness.light,
        seedColor: currentSeedColor,
      );

  ThemeData get darkTheme => AppTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: currentSeedColor,
      );

  void init() {
    _loadSettings();
    _colorService.addListener(_onColorsChanged);
    _playbackManager.addListener(_onPlaybackChanged);
    
    // Extract colors for the initial song if there is one
    if (_playbackManager.currentSong != null) {
      _colorService.extractColorsForSong(_playbackManager.currentSong);
    }
  }

  void _onPlaybackChanged() {
    if (_playbackManager.currentSong != null) {
      _colorService.extractColorsForSong(_playbackManager.currentSong);
    }
  }

  void _loadSettings() {
    final modeIndex = sharedPrefs.getInt(_themeModeKey);
    if (modeIndex != null && modeIndex >= 0 && modeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[modeIndex];
      // If they previously had 'system' selected, migrate them to 'dark'
      if (_themeMode == ThemeMode.system) {
        _themeMode = ThemeMode.dark;
      }
    } else {
      _themeMode = ThemeMode.dark; // Default to dark like before
    }

    final sourceIndex = sharedPrefs.getInt(_themeSourceKey);
    if (sourceIndex != null && sourceIndex >= 0 && sourceIndex < ThemeSource.values.length) {
      _themeSource = ThemeSource.values[sourceIndex];
    }

    final presetValue = sharedPrefs.getInt(_presetColorKey);
    if (presetValue != null) _presetColor = Color(presetValue);

    final customValue = sharedPrefs.getInt(_customColorKey);
    if (customValue != null) _customColor = Color(customValue);

    final staticValue = sharedPrefs.getInt(_staticCoverArtColorKey);
    if (staticValue != null) _staticCoverArtColor = Color(staticValue);
  }

  void _onColorsChanged() {
    if (_themeSource == ThemeSource.dynamicCoverArt) {
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await sharedPrefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> setThemeSource(ThemeSource source) async {
    if (_themeSource == source) return;
    _themeSource = source;
    await sharedPrefs.setInt(_themeSourceKey, source.index);
    notifyListeners();
  }

  Future<void> setPresetColor(Color color) async {
    if (_presetColor == color) return;
    _presetColor = color;
    await sharedPrefs.setInt(_presetColorKey, color.value);
    if (_themeSource == ThemeSource.preset) {
      notifyListeners();
    }
  }

  Future<void> setCustomColor(Color color) async {
    if (_customColor == color) return;
    _customColor = color;
    await sharedPrefs.setInt(_customColorKey, color.value);
    if (_themeSource == ThemeSource.custom) {
      notifyListeners();
    }
  }

  Future<void> setStaticCoverArtColor(Color color) async {
    if (_staticCoverArtColor == color) return;
    _staticCoverArtColor = color;
    await sharedPrefs.setInt(_staticCoverArtColorKey, color.value);
    if (_themeSource == ThemeSource.staticCoverArt) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _colorService.removeListener(_onColorsChanged);
    _playbackManager.removeListener(_onPlaybackChanged);
    super.dispose();
  }
}
