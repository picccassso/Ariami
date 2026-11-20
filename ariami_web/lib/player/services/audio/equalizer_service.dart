import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/equalizer_presets.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_host.dart';

export 'package:ariami_core/models/equalizer_presets.dart' show EqParameters;

class EqualizerService extends ChangeNotifier {
  static final EqualizerService _instance = EqualizerService._internal();
  factory EqualizerService() => _instance;
  EqualizerService._internal();

  static const String customPresetName = 'Custom';

  static const String _enabledKey = 'eq_enabled';
  static const String _selectedPresetKey = 'eq_selected_preset';
  static const String _customGainsKey = 'eq_custom_gains';
  static const String _userPresetsKey = 'eq_user_presets';
  static const String _flatPresetName = 'Flat';

  static const Duration _persistDebounce = Duration(milliseconds: 400);

  EqualizerBackend? _backend;
  EqParameters? _parameters;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _isEnabled = false;
  String _selectedPresetName = _flatPresetName;
  List<EqualizerPoint> _customCurve = canonicalEqualizerCurve(
    equalizerBuiltInPresetGains[_flatPresetName]!,
  );
  List<UserEqualizerPreset> _userPresets = [];
  List<double> _currentBandGains = [];
  Timer? _persistTimer;

  bool get isSupported => _backend?.isSupported ?? false;
  bool get isEnabled => _isEnabled;
  String get selectedPresetName => _selectedPresetName;
  List<String> get builtInPresetNames =>
      equalizerBuiltInPresetGains.keys.toList(growable: false);
  List<String> get userPresetNames =>
      _userPresets.map((preset) => preset.name).toList(growable: false);
  EqParameters? get parameters => _parameters;
  List<double> get currentBandGains =>
      List<double>.unmodifiable(_currentBandGains);

  void configure(EqualizerBackend? backend) {
    if (identical(_backend, backend)) return;
    _backend = backend;
    if (_initialized) {
      unawaited(_syncAfterConfigure());
    }
  }

  Future<void> _syncAfterConfigure() async {
    if (isSupported && _parameters == null) {
      _parameters = const EqParameters(
        minDecibels: -12,
        maxDecibels: 12,
        bandFrequencies: equalizerCanonicalFrequencies,
      );
      _currentBandGains =
          List<double>.filled(equalizerCanonicalFrequencies.length, 0);
    }
    if (isSupported) {
      await _applyCurveToDevice(_activeCurve);
    }
    notifyListeners();
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializeFuture ??= _initialize();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    await _saveEnabled();
    await _applyToBackend();
    notifyListeners();
  }

  Future<void> applyPreset(String name) async {
    final curve = _curveForPreset(name);
    if (curve == null) {
      throw ArgumentError.value(name, 'name', 'Unknown equalizer preset');
    }

    _selectedPresetName = name;
    await _applyCurveToDevice(curve);
    await _saveSelectedPreset();
    notifyListeners();
  }

  Future<void> resetToFlat() => applyPreset(_flatPresetName);

  Future<void> setBandGain(int bandIndex, double gainDb) async {
    final params = _parameters;
    if (params == null) return;
    RangeError.checkValidIndex(bandIndex, params.bandFrequencies, 'bandIndex');

    final clampedGain = _clampGain(gainDb, params);
    if (_currentBandGains.length != params.bandCount) {
      _currentBandGains = List<double>.filled(params.bandCount, 0);
    }
    _currentBandGains[bandIndex] = clampedGain;
    await _applyToBackend();
    _selectedPresetName = customPresetName;
    _customCurve = _currentDeviceCurve(params);

    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _saveSelectedPreset();
      _saveCustomCurve();
    });
    notifyListeners();
  }

  Future<void> saveCurrentAsPreset(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Preset name cannot be empty');
    }
    if (isReservedPresetName(normalizedName)) {
      throw ArgumentError.value(
        name,
        'name',
        'Preset name is reserved',
      );
    }

    final params = _parameters;
    if (params == null) return;

    final preset = UserEqualizerPreset(
      normalizedName,
      _currentDeviceCurve(params),
    );
    final existingIndex = _userPresets.indexWhere(
      (userPreset) => userPreset.name == normalizedName,
    );
    if (existingIndex == -1) {
      _userPresets = [..._userPresets, preset];
    } else {
      _userPresets = [
        ..._userPresets.take(existingIndex),
        preset,
        ..._userPresets.skip(existingIndex + 1),
      ];
    }

    _selectedPresetName = normalizedName;
    await _saveUserPresets();
    await _saveSelectedPreset();
    notifyListeners();
  }

  bool isReservedPresetName(String name) {
    final lowerName = name.trim().toLowerCase();
    if (lowerName == customPresetName.toLowerCase()) return true;
    return equalizerBuiltInPresetGains.keys.any(
      (presetName) => presetName.toLowerCase() == lowerName,
    );
  }

  Future<void> deleteUserPreset(String name) async {
    final existingIndex = _userPresets.indexWhere(
      (preset) => preset.name == name,
    );
    if (existingIndex == -1) return;

    _userPresets = [
      ..._userPresets.take(existingIndex),
      ..._userPresets.skip(existingIndex + 1),
    ];

    if (_selectedPresetName == name) {
      _selectedPresetName = customPresetName;
      final params = _parameters;
      if (params != null) {
        _customCurve = _currentDeviceCurve(params);
        await _saveCustomCurve();
      }
      await _saveSelectedPreset();
    }

    await _saveUserPresets();
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _initializeFuture = null;
    _initialized = false;
    _isEnabled = false;
    _selectedPresetName = _flatPresetName;
    _customCurve =
        canonicalEqualizerCurve(equalizerBuiltInPresetGains[_flatPresetName]!);
    _userPresets = <UserEqualizerPreset>[];
    _currentBandGains = <double>[];
    _parameters = null;
  }

  Future<void> _initialize() async {
    await _loadPrefs();

    if (isSupported) {
      _parameters = const EqParameters(
        minDecibels: -12,
        maxDecibels: 12,
        bandFrequencies: equalizerCanonicalFrequencies,
      );
      _currentBandGains =
          List<double>.filled(equalizerCanonicalFrequencies.length, 0);
      try {
        await _applyCurveToDevice(_activeCurve);
      } catch (e) {
        debugPrint('[EqualizerService] Error applying equalizer state: $e');
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_enabledKey) ?? false;
      _selectedPresetName =
          prefs.getString(_selectedPresetKey) ?? _flatPresetName;
      _customCurve = decodeEqualizerCurve(prefs.getString(_customGainsKey)) ??
          canonicalEqualizerCurve(equalizerBuiltInPresetGains[_flatPresetName]!);
      _userPresets =
          decodeUserEqualizerPresets(prefs.getString(_userPresetsKey)) ?? [];

      if (_curveForPreset(_selectedPresetName) == null) {
        _selectedPresetName = customPresetName;
      }
    } catch (e) {
      debugPrint('[EqualizerService] Error loading settings: $e');
      _isEnabled = false;
      _selectedPresetName = _flatPresetName;
      _customCurve =
          canonicalEqualizerCurve(equalizerBuiltInPresetGains[_flatPresetName]!);
      _userPresets = [];
    }
  }

  Future<void> _saveEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, _isEnabled);
    } catch (e) {
      debugPrint('[EqualizerService] Error saving enabled state: $e');
    }
  }

  Future<void> _saveSelectedPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedPresetKey, _selectedPresetName);
    } catch (e) {
      debugPrint('[EqualizerService] Error saving selected preset: $e');
    }
  }

  Future<void> _saveCustomCurve() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _customGainsKey,
        jsonEncode(encodeEqualizerCurve(_customCurve)),
      );
    } catch (e) {
      debugPrint('[EqualizerService] Error saving custom gains: $e');
    }
  }

  Future<void> _saveUserPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _userPresetsKey,
        jsonEncode(_userPresets.map((preset) => preset.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[EqualizerService] Error saving user presets: $e');
    }
  }

  Future<void> _applyToBackend() async {
    final backend = _backend;
    if (backend == null || !backend.isSupported) return;
    await backend.apply(
      enabled: _isEnabled,
      frequencies: equalizerCanonicalFrequencies
          .map((frequency) => frequency.round())
          .toList(growable: false),
      gains: _currentBandGains,
    );
  }

  Future<void> _applyCurveToDevice(List<EqualizerPoint> curve) async {
    final params = _parameters;
    if (params == null) return;

    final gains = <double>[];
    for (var i = 0; i < params.bandCount; i++) {
      final gain = _clampGain(
        interpolateEqualizerGain(curve, params.bandFrequencies[i]),
        params,
      );
      gains.add(gain);
    }
    _currentBandGains = gains;
    await _applyToBackend();
  }

  List<EqualizerPoint> get _activeCurve =>
      _curveForPreset(_selectedPresetName) ?? _customCurve;

  List<EqualizerPoint>? _curveForPreset(String name) {
    if (name == customPresetName) return _customCurve;

    final builtInGains = equalizerBuiltInPresetGains[name];
    if (builtInGains != null) {
      return canonicalEqualizerCurve(builtInGains);
    }

    for (final userPreset in _userPresets) {
      if (userPreset.name == name) return userPreset.curve;
    }
    return null;
  }

  double _clampGain(double gain, EqParameters params) {
    return gain.clamp(params.minDecibels, params.maxDecibels).toDouble();
  }

  List<EqualizerPoint> _currentDeviceCurve(EqParameters params) {
    return [
      for (var i = 0; i < params.bandCount; i++)
        EqualizerPoint(
          params.bandFrequencies[i],
          i < _currentBandGains.length ? _currentBandGains[i] : 0,
        ),
    ];
  }
}
