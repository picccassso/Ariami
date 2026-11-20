import 'dart:async';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_models.dart';
import '../theme/dynamic_theme_seed.dart';
import '../theme/player_theme.dart';
import '../widgets/artwork_image_provider.dart';
import 'player_api_client.dart';

enum AppearanceSource {
  systemNeutral,
  lightNeutral,
  darkNeutral,
  preset,
  custom,
  dynamicCoverArt,
}

/// Manages the player's appearance: neutral / preset / custom / dynamic.
///
/// For [AppearanceSource.dynamicCoverArt] the dominant colour of the current
/// track's artwork is extracted with [PaletteGenerator] and used as the theme
/// seed.
class ThemeController extends ChangeNotifier {
  static const _sourceKey = 'player_appearance_source';
  static const _presetKey = 'player_preset_color';
  static const _customKey = 'player_custom_color';
  static const _amoledBlackKey = 'player_amoled_black';
  static const _movingBackdropKey = 'player_moving_backdrop';
  static const _musicVisualizerKey = 'player_music_visualizer';

  static const List<Color> presetSwatches = <Color>[
    Color(0xFF1DB954), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
    Color(0xFFE53935), // red
    Color(0xFFFB8C00), // orange
    Color(0xFF00ACC1), // teal
    Color(0xFFD81B60), // pink
    Color(0xFFFDD835), // yellow
  ];

  AppearanceSource _source = AppearanceSource.darkNeutral;
  Color _presetColor = const Color(0xFF1DB954);
  Color _customColor = const Color(0xFF8E24AA);
  Color _dynamicColor = const Color(0xFF6E7A86); // neutral until art loads
  List<Color>? _dynamicAmbient;
  List<Color> _artworkColors = const [];
  bool _amoledBlack = false;
  bool _movingBackdrop = false;
  bool _musicVisualizer = false;

  PlayerApiClient? _client;
  Track? _currentTrack;
  String? _lastExtractedKey;
  int _artworkRequest = 0;
  Timer? _persistTimer;

  AppearanceSource get source => _source;
  Color get presetColor => _presetColor;
  Color get customColor => _customColor;

  bool get amoledBlack => _amoledBlack;
  bool get movingBackdrop => _movingBackdrop;

  /// Whether the full-screen player's backdrop becomes the music visualizer
  /// while music plays here. Off by default: it flashes and keeps the GPU
  /// busy.
  bool get musicVisualizer => _musicVisualizer;

  /// The cover's own main colours for the music visualizer in cover-art
  /// mode (see [selectArtworkColors]); empty otherwise, when it paints with
  /// the theme's glows.
  List<Color> get artworkColors =>
      _source == AppearanceSource.dynamicCoverArt ? _artworkColors : const [];

  ThemeMode get themeMode {
    switch (_source) {
      case AppearanceSource.systemNeutral:
        return ThemeMode.system;
      case AppearanceSource.lightNeutral:
        return ThemeMode.light;
      default:
        return ThemeMode.dark;
    }
  }

  bool get _isNeutral =>
      _source == AppearanceSource.systemNeutral ||
      _source == AppearanceSource.lightNeutral ||
      _source == AppearanceSource.darkNeutral;

  /// True when the active appearance is seeded from a colour (preset / custom /
  /// cover art) rather than a neutral black/white theme. Used by surfaces that
  /// only tint themselves in colour-source mode (e.g. the detail header).
  bool get isColorSource => !_isNeutral;

  Color get seedColor {
    switch (_source) {
      case AppearanceSource.preset:
        return _presetColor;
      case AppearanceSource.custom:
        return _customColor;
      case AppearanceSource.dynamicCoverArt:
        return _dynamicColor;
      default:
        return PlayerTheme.accent;
    }
  }

  /// Backdrop glow colours for colour-source themes: the artwork's own
  /// palette in cover-art mode, otherwise derived from the seed.
  List<Color>? get _ambient =>
      _source == AppearanceSource.dynamicCoverArt ? _dynamicAmbient : null;

  ThemeData get lightTheme => _isNeutral
      ? PlayerTheme.neutral(brightness: Brightness.light)
      : PlayerTheme.colorSource(
          seedColor,
          ambient: _ambient,
          amoled: _amoledBlack,
        );

  ThemeData get darkTheme => _isNeutral
      ? PlayerTheme.neutral(brightness: Brightness.dark, amoled: _amoledBlack)
      : PlayerTheme.colorSource(
          seedColor,
          ambient: _ambient,
          amoled: _amoledBlack,
        );

  ThemeData resolveTheme(Brightness platformBrightness) {
    final useLight = themeMode == ThemeMode.light ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.light);
    return useLight ? lightTheme : darkTheme;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sourceIndex = prefs.getInt(_sourceKey);
    if (sourceIndex != null &&
        sourceIndex >= 0 &&
        sourceIndex < AppearanceSource.values.length) {
      _source = AppearanceSource.values[sourceIndex];
    }
    final preset = prefs.getInt(_presetKey);
    if (preset != null) _presetColor = Color(preset);
    final custom = prefs.getInt(_customKey);
    if (custom != null) _customColor = Color(custom);
    _amoledBlack = prefs.getBool(_amoledBlackKey) ?? false;
    _movingBackdrop = prefs.getBool(_movingBackdropKey) ?? false;
    _musicVisualizer = prefs.getBool(_musicVisualizerKey) ?? false;
    notifyListeners();
  }

  void attach(PlayerApiClient? client) {
    _client = client;
    _lastExtractedKey = null;
    _artworkRequest++;
    if (_source == AppearanceSource.dynamicCoverArt &&
        client != null &&
        _currentTrack != null) {
      unawaited(_extractArtworkColor(_currentTrack!));
    }
  }

  void setSource(AppearanceSource source) {
    if (_source == source) return;
    _source = source;
    if (source == AppearanceSource.dynamicCoverArt && _currentTrack != null) {
      unawaited(_extractArtworkColor(_currentTrack!));
    } else if (source != AppearanceSource.dynamicCoverArt) {
      // Prevent an extraction started in cover-art mode from updating the
      // stored dynamic colour after the user has switched away.
      _artworkRequest++;
    }
    notifyListeners();
    _schedulePersist();
  }

  void setPresetColor(Color color) {
    _presetColor = color;
    _source = AppearanceSource.preset;
    notifyListeners();
    _schedulePersist();
  }

  void setCustomColor(Color color) {
    _customColor = color;
    _source = AppearanceSource.custom;
    notifyListeners();
    _schedulePersist();
  }

  void setAmoledBlack(bool enabled) {
    if (_amoledBlack == enabled) return;
    _amoledBlack = enabled;
    notifyListeners();
    _schedulePersist();
  }

  void setMovingBackdrop(bool enabled) {
    if (_movingBackdrop == enabled) return;
    _movingBackdrop = enabled;
    notifyListeners();
    _schedulePersist();
  }

  void setMusicVisualizer(bool enabled) {
    if (_musicVisualizer == enabled) return;
    _musicVisualizer = enabled;
    notifyListeners();
    _schedulePersist();
  }

  /// Writes are debounced so the live colour picker (which fires on every drag
  /// frame) doesn't thrash the disk; in-memory state and listeners update
  /// immediately so the UI stays responsive.
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 300), _persist);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sourceKey, _source.index);
    await prefs.setInt(_presetKey, _presetColor.toARGB32());
    await prefs.setInt(_customKey, _customColor.toARGB32());
    await prefs.setBool(_amoledBlackKey, _amoledBlack);
    await prefs.setBool(_movingBackdropKey, _movingBackdrop);
    await prefs.setBool(_musicVisualizerKey, _musicVisualizer);
  }

  @override
  void dispose() {
    // Flush any pending change so a quick quit doesn't lose the last pick.
    if (_persistTimer?.isActive ?? false) {
      _persistTimer!.cancel();
      _persist();
    }
    super.dispose();
  }

  /// Called when the current track changes. Extracts dominant artwork colour
  /// when the dynamic source is active.
  Future<void> onTrackChanged(Track? track) async {
    // Retain the track even while another appearance source is active. This
    // lets switching to cover-art mode immediately colour the UI from the song
    // that is already playing, instead of waiting for the next track change.
    _currentTrack = track;
    if (_source != AppearanceSource.dynamicCoverArt) return;
    if (track == null) {
      _artworkRequest++;
      return;
    }
    await _extractArtworkColor(track);
  }

  Future<void> _extractArtworkColor(Track track) async {
    final client = _client;
    if (client == null) return;

    final key =
        track.albumId != null ? 'album:${track.albumId}' : 'song:${track.id}';
    if (key == _lastExtractedKey) return;
    _lastExtractedKey = key;
    final request = ++_artworkRequest;

    final url = track.albumId != null
        ? client.albumArtworkUrl(track.albumId!, thumbnail: true)
        : client.songArtworkUrl(track.id, thumbnail: true);

    try {
      // Shared artwork disk cache: the grid and media controls use the same
      // thumbnail bytes, so extraction is usually a local read.
      final bytes = await ArtworkImageProvider.loadBytes(
        url,
        headers: client.artworkHeaders,
      ).timeout(const Duration(seconds: 8));
      if (bytes.isEmpty) return;
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(120, 120),
        maximumColorCount: 16,
      );
      final color = _seedFromPalette(palette);
      if (color != null &&
          request == _artworkRequest &&
          _source == AppearanceSource.dynamicCoverArt) {
        _dynamicColor = color;
        _dynamicAmbient = selectAmbientColors(_swatches(palette), color);
        _artworkColors = selectArtworkColors(_swatches(palette));
        notifyListeners();
      }
    } catch (_) {
      // Keep the previous colour on failure.
    }
  }

  /// Picks a representative colour from [palette] to seed the theme.
  /// Population prevents a tiny accent detail from overpowering the artwork,
  /// while saturation still lets a substantial colour beat a neutral backdrop.
  Color? _seedFromPalette(PaletteGenerator palette) {
    return selectDynamicThemeSeed(_swatches(palette));
  }

  Iterable<({Color color, int population})> _swatches(
    PaletteGenerator palette,
  ) {
    return palette.paletteColors.map(
      (swatch) => (color: swatch.color, population: swatch.population),
    );
  }
}
