import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/equalizer_presets.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:ariami_core/models/equalizer_presets.dart' show EqParameters;

/// Service for managing the graphic equalizer on Android and iOS.
///
/// Presets are stored as frequency curves so they can be projected onto the
/// platform-specific equalizer bands (device-dependent on Android, fixed on
/// iOS where the fork's DarwinEqualizer lets us choose the layout).
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

  // Both effects are created eagerly so the audio handler can build its
  // AudioPipeline before initialize() runs; only the current platform's
  // effect is ever activated by just_audio.
  final AndroidEqualizer androidEqualizer = AndroidEqualizer();
  final DarwinEqualizer darwinEqualizer = DarwinEqualizer(
    frequencies: equalizerCanonicalFrequencies,
  );

  AndroidEqualizerParameters? _androidParameters;
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

  static bool get isAndroidPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static bool get isDarwinPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  bool get isSupported => isAndroidPlatform || isDarwinPlatform;

  bool get isEnabled => _isEnabled;
  String get selectedPresetName => _selectedPresetName;
  List<String> get builtInPresetNames =>
      equalizerBuiltInPresetGains.keys.toList(growable: false);
  List<String> get userPresetNames =>
      _userPresets.map((preset) => preset.name).toList(growable: false);

  /// Null on Android until the platform reports its bands (which requires
  /// audio playback to have started once); available immediately on iOS.
  EqParameters? get parameters => _parameters;
  List<double> get currentBandGains =>
      List<double>.unmodifiable(_currentBandGains);

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializeFuture ??= _initialize();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    await _saveEnabled();
    await _applyEnabled();
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

  /// Resets every band to 0 dB and selects the Flat preset.
  Future<void> resetToFlat() => applyPreset(_flatPresetName);

  Future<void> setBandGain(int bandIndex, double gainDb) async {
    final params = _parameters;
    if (params == null) return;
    RangeError.checkValidIndex(bandIndex, params.bandFrequencies, 'bandIndex');

    final clampedGain = _clampGain(gainDb, params);
    await _setDeviceBandGain(bandIndex, clampedGain);

    if (_currentBandGains.length != params.bandCount) {
      _currentBandGains = List<double>.filled(params.bandCount, 0);
    }
    _currentBandGains[bandIndex] = clampedGain;
    _selectedPresetName = customPresetName;
    _customCurve = _currentDeviceCurve(params);

    // Slider drags call this many times a second; debounce the disk writes.
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

  /// Whether [name] clashes with a built-in preset or the Custom sentinel
  /// and therefore cannot be used for a user preset.
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

  Future<void> _initialize() async {
    await _loadPrefs();

    if (isSupported) {
      try {
        // Safe before the platform player exists: just_audio stores the flag
        // and carries it into the platform init request on activation.
        await _applyEnabled();
      } catch (e) {
        debugPrint('[EqualizerService] Error applying enabled state: $e');
      }
      if (isDarwinPlatform) {
        // The fork's DarwinEqualizer has a fixed band layout known upfront.
        final darwinParams = darwinEqualizer.parameters;
        _parameters = EqParameters(
          minDecibels: darwinParams.minDecibels,
          maxDecibels: darwinParams.maxDecibels,
          bandFrequencies: darwinParams.bands
              .map((band) => band.centerFrequency)
              .toList(growable: false),
        );
        _currentBandGains =
            darwinParams.bands.map((band) => band.gain).toList();
        await _applyCurveToDevice(_activeCurve);
      } else {
        _watchAndroidParameters();
      }
    }

    _initialized = true;
    notifyListeners();
    debugPrint('[EqualizerService] Initialized');
  }

  /// On Android the equalizer parameters future only completes once
  /// just_audio creates the real platform player (on the first load of an
  /// audio source), so initialization must not block on it. Apply the
  /// persisted curve whenever the device bands become available.
  void _watchAndroidParameters() {
    androidEqualizer.parameters.then((params) async {
      _androidParameters = params;
      _parameters = EqParameters(
        minDecibels: params.minDecibels,
        maxDecibels: params.maxDecibels,
        bandFrequencies: params.bands
            .map((band) => band.centerFrequency)
            .toList(growable: false),
      );
      _currentBandGains = params.bands.map((band) => band.gain).toList();
      await _applyCurveToDevice(_activeCurve);
      notifyListeners();
    }).catchError((Object e) {
      debugPrint('[EqualizerService] Error loading equalizer parameters: $e');
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_enabledKey) ?? false;
      _selectedPresetName =
          prefs.getString(_selectedPresetKey) ?? _flatPresetName;
      _customCurve = decodeEqualizerCurve(prefs.getString(_customGainsKey)) ??
          canonicalEqualizerCurve(equalizerBuiltInPresetGains[_flatPresetName]!);
      _userPresets = decodeUserEqualizerPresets(prefs.getString(_userPresetsKey)) ?? [];

      if (_curveForPreset(_selectedPresetName) == null) {
        _selectedPresetName = customPresetName;
      }
    } catch (e) {
      debugPrint('[EqualizerService] Error loading settings: $e');
      _isEnabled = false;
      _selectedPresetName = _flatPresetName;
      _customCurve = canonicalEqualizerCurve(equalizerBuiltInPresetGains[_flatPresetName]!);
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

  Future<void> _applyEnabled() async {
    if (isAndroidPlatform) {
      await androidEqualizer.setEnabled(_isEnabled);
    } else if (isDarwinPlatform) {
      await darwinEqualizer.setEnabled(_isEnabled);
    }
  }

  Future<void> _setDeviceBandGain(int bandIndex, double gainDb) async {
    if (isAndroidPlatform) {
      final params = _androidParameters;
      if (params == null) return;
      await params.bands[bandIndex].setGain(gainDb);
    } else if (isDarwinPlatform) {
      await darwinEqualizer.parameters.bands[bandIndex].setGain(gainDb);
    }
  }

  /// No-op until the device parameters are known; on Android
  /// [_watchAndroidParameters] re-applies the active curve as soon as they
  /// arrive.
  Future<void> _applyCurveToDevice(List<EqualizerPoint> curve) async {
    final params = _parameters;
    if (params == null) return;

    final gains = <double>[];
    for (var i = 0; i < params.bandCount; i++) {
      final gain = _clampGain(
        interpolateEqualizerGain(curve, params.bandFrequencies[i]),
        params,
      );
      await _setDeviceBandGain(i, gain);
      gains.add(gain);
    }
    _currentBandGains = gains;
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
