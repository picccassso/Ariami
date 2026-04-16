import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart'; // For sharedPrefs
import '../utils/constants.dart';
import 'color_extraction_service.dart';
import 'playback_manager.dart';

enum ThemeSource {
  systemNeutral,
  lightNeutral,
  darkNeutral,
  preset,
  custom,
  dynamicCoverArt,
  staticCoverArt,
}

enum _LegacyThemeSource {
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
  static const String _themeSourceKey = 'theme_source'; // Legacy key
  static const String _appearanceSourceKey = 'appearance_source';
  static const String _presetColorKey = 'theme_preset_color';
  static const String _customColorKey = 'theme_custom_color';
  static const String _staticCoverArtColorKey = 'theme_static_cover_art_color';
  static const String _staticSongIdKey = 'static_song_id';
  static const String _staticSongTitleKey = 'static_song_title';
  static const String _staticSongArtistKey = 'static_song_artist';
  static const String _staticSongAlbumIdKey = 'static_song_album_id';

  final ColorExtractionService _colorService = ColorExtractionService();
  final PlaybackManager _playbackManager = PlaybackManager();

  ThemeSource _themeSource = ThemeSource.systemNeutral;

  Color _presetColor = const Color(0xFFFFFFFF); // Default pure white
  Color _customColor = const Color(0xFFFFFFFF);
  Color _staticCoverArtColor = const Color(0xFFFFFFFF);

  String? _staticSongId;
  String? _staticSongTitle;
  String? _staticSongArtist;
  String? _staticSongAlbumId;

  ThemeMode get themeMode {
    switch (_themeSource) {
      case ThemeSource.systemNeutral:
        return ThemeMode.system;
      case ThemeSource.lightNeutral:
        return ThemeMode.light;
      case ThemeSource.darkNeutral:
        return ThemeMode.dark;
      case ThemeSource.preset:
      case ThemeSource.custom:
      case ThemeSource.dynamicCoverArt:
      case ThemeSource.staticCoverArt:
        // For color-based sources, light/dark selection is intentionally ignored.
        return ThemeMode.dark;
    }
  }

  ThemeSource get themeSource => _themeSource;
  Color get presetColor => _presetColor;
  Color get customColor => _customColor;
  Color get staticCoverArtColor => _staticCoverArtColor;
  String? get staticSongId => _staticSongId;
  String? get staticSongTitle => _staticSongTitle;
  String? get staticSongArtist => _staticSongArtist;
  String? get staticSongAlbumId => _staticSongAlbumId;

  bool get _isNeutralSource {
    switch (_themeSource) {
      case ThemeSource.systemNeutral:
      case ThemeSource.lightNeutral:
      case ThemeSource.darkNeutral:
        return true;
      case ThemeSource.preset:
      case ThemeSource.custom:
      case ThemeSource.dynamicCoverArt:
      case ThemeSource.staticCoverArt:
        return false;
    }
  }

  Color get currentSeedColor {
    switch (_themeSource) {
      case ThemeSource.systemNeutral:
      case ThemeSource.lightNeutral:
      case ThemeSource.darkNeutral:
        return Colors.white;
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

  ThemeData get lightTheme {
    if (_isNeutralSource) {
      return AppTheme.buildNeutralTheme(brightness: Brightness.light);
    }

    return AppTheme.buildColorSourceTheme(seedColor: currentSeedColor);
  }

  ThemeData get darkTheme {
    if (_isNeutralSource) {
      return AppTheme.buildNeutralTheme(brightness: Brightness.dark);
    }

    return AppTheme.buildColorSourceTheme(seedColor: currentSeedColor);
  }

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
    final presetValue = sharedPrefs.getInt(_presetColorKey);
    if (presetValue != null) _presetColor = Color(presetValue);

    final customValue = sharedPrefs.getInt(_customColorKey);
    if (customValue != null) _customColor = Color(customValue);

    final staticValue = sharedPrefs.getInt(_staticCoverArtColorKey);
    if (staticValue != null) _staticCoverArtColor = Color(staticValue);

    _staticSongId = sharedPrefs.getString(_staticSongIdKey);
    _staticSongTitle = sharedPrefs.getString(_staticSongTitleKey);
    _staticSongArtist = sharedPrefs.getString(_staticSongArtistKey);
    _staticSongAlbumId = sharedPrefs.getString(_staticSongAlbumIdKey);

    // First try the new unified appearance source model.
    final sourceIndex = sharedPrefs.getInt(_appearanceSourceKey);
    if (sourceIndex != null &&
        sourceIndex >= 0 &&
        sourceIndex < ThemeSource.values.length) {
      _themeSource = ThemeSource.values[sourceIndex];
      return;
    }

    // Fallback migration from legacy split keys (theme_mode + theme_source).
    _themeSource = _migrateLegacySelection();
    unawaited(sharedPrefs.setInt(_appearanceSourceKey, _themeSource.index));
  }

  ThemeSource _migrateLegacySelection() {
    final legacySource = _readLegacyThemeSource();
    final legacyMode = _readLegacyThemeMode() ?? ThemeMode.dark;

    if (legacySource == null) {
      return ThemeSource.systemNeutral;
    }

    if (legacySource == _LegacyThemeSource.preset &&
        _presetColor.toARGB32() == Colors.white.toARGB32()) {
      return _neutralSourceFromMode(legacyMode);
    }

    switch (legacySource) {
      case _LegacyThemeSource.preset:
        return ThemeSource.preset;
      case _LegacyThemeSource.custom:
        return ThemeSource.custom;
      case _LegacyThemeSource.dynamicCoverArt:
        return ThemeSource.dynamicCoverArt;
      case _LegacyThemeSource.staticCoverArt:
        return ThemeSource.staticCoverArt;
    }
  }

  _LegacyThemeSource? _readLegacyThemeSource() {
    final sourceIndex = sharedPrefs.getInt(_themeSourceKey);
    if (sourceIndex == null ||
        sourceIndex < 0 ||
        sourceIndex >= _LegacyThemeSource.values.length) {
      return null;
    }

    return _LegacyThemeSource.values[sourceIndex];
  }

  ThemeMode? _readLegacyThemeMode() {
    final modeIndex = sharedPrefs.getInt(_themeModeKey);
    if (modeIndex == null ||
        modeIndex < 0 ||
        modeIndex >= ThemeMode.values.length) {
      return null;
    }

    return ThemeMode.values[modeIndex];
  }

  ThemeSource _neutralSourceFromMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return ThemeSource.systemNeutral;
      case ThemeMode.light:
        return ThemeSource.lightNeutral;
      case ThemeMode.dark:
        return ThemeSource.darkNeutral;
    }
  }

  void _onColorsChanged() {
    if (_themeSource == ThemeSource.dynamicCoverArt) {
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await setThemeSource(_neutralSourceFromMode(mode));
  }

  Future<void> setThemeSource(ThemeSource source) async {
    if (_themeSource == source) return;
    _themeSource = source;
    await sharedPrefs.setInt(_appearanceSourceKey, source.index);
    notifyListeners();
  }

  Future<void> setPresetColor(Color color) async {
    if (_presetColor == color) return;
    _presetColor = color;
    await sharedPrefs.setInt(_presetColorKey, color.toARGB32());
    if (_themeSource == ThemeSource.preset) {
      notifyListeners();
    }
  }

  Future<void> setCustomColor(Color color) async {
    if (_customColor == color) return;
    _customColor = color;
    await sharedPrefs.setInt(_customColorKey, color.toARGB32());
    if (_themeSource == ThemeSource.custom) {
      notifyListeners();
    }
  }

  Future<void> setStaticCoverArtColor(Color color) async {
    if (_staticCoverArtColor == color) return;
    _staticCoverArtColor = color;
    await sharedPrefs.setInt(_staticCoverArtColorKey, color.toARGB32());
    if (_themeSource == ThemeSource.staticCoverArt) {
      notifyListeners();
    }
  }

  Future<void> setStaticSong(
    String id,
    String title,
    String artist,
    String? albumId,
    Color color,
  ) async {
    _staticSongId = id;
    _staticSongTitle = title;
    _staticSongArtist = artist;
    _staticSongAlbumId = albumId;
    _staticCoverArtColor = color;
    await Future.wait([
      sharedPrefs.setString(_staticSongIdKey, id),
      sharedPrefs.setString(_staticSongTitleKey, title),
      sharedPrefs.setString(_staticSongArtistKey, artist),
      if (albumId != null)
        sharedPrefs.setString(_staticSongAlbumIdKey, albumId)
      else
        sharedPrefs.remove(_staticSongAlbumIdKey),
      sharedPrefs.setInt(_staticCoverArtColorKey, color.toARGB32()),
    ]);
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
