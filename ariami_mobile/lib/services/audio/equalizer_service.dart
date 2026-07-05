import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified view of the device equalizer's capabilities, independent of
/// whether the platform effect is [AndroidEqualizer] or [DarwinEqualizer].
class EqParameters {
  final double minDecibels;
  final double maxDecibels;
  final List<double> bandFrequencies;

  const EqParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bandFrequencies,
  });

  int get bandCount => bandFrequencies.length;
}

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

  static const List<double> _canonicalFrequencies = [
    60,
    230,
    910,
    3600,
    14000,
  ];

  static const Map<String, List<double>> _builtInPresetGains = {
    'Flat': [0, 0, 0, 0, 0],
    'Bass Boost': [5, 4, 1.5, 0, 0],
    'Treble Boost': [0, 0, 1, 3.5, 5],
    'Rock': [4, 2, -1, 2.5, 4],
    'Pop': [-1, 2.5, 4, 2, -0.5],
    'Jazz': [2.5, 1.5, 0, 2, 3],
    'Classical': [2, 1, 0, 1.5, 2.5],
    'Vocal': [-2, -1, 3.5, 3, 1],
    'Electronic': [4.5, 2, 0, 2.5, 4.5],
  };

  // Both effects are created eagerly so the audio handler can build its
  // AudioPipeline before initialize() runs; only the current platform's
  // effect is ever activated by just_audio.
  final AndroidEqualizer androidEqualizer = AndroidEqualizer();
  final DarwinEqualizer darwinEqualizer = DarwinEqualizer(
    frequencies: _canonicalFrequencies,
  );

  AndroidEqualizerParameters? _androidParameters;
  EqParameters? _parameters;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _isEnabled = false;
  String _selectedPresetName = _flatPresetName;
  List<_EqualizerPoint> _customCurve = _canonicalCurve(
    _builtInPresetGains[_flatPresetName]!,
  );
  List<_UserEqualizerPreset> _userPresets = [];
  List<double> _currentBandGains = [];
  Timer? _persistTimer;

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static bool get _isDarwin {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  bool get isSupported => _isAndroid || _isDarwin;

  bool get isEnabled => _isEnabled;
  String get selectedPresetName => _selectedPresetName;
  List<String> get builtInPresetNames =>
      _builtInPresetGains.keys.toList(growable: false);
  List<String> get userPresetNames =>
      _userPresets.map((preset) => preset.name).toList(growable: false);

  /// Null on Android until the platform reports its bands (which requires
  /// audio playback to have started once); available immediately on iOS.
  EqParameters? get parameters => _parameters;
  List<double> get currentBandGains =>
      List<double>.unmodifiable(_currentBandGains);

  /// Load persisted state and apply it to the platform equalizer.
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

    final preset = _UserEqualizerPreset(
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
    return _builtInPresetGains.keys.any(
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
      if (_isDarwin) {
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
      _customCurve = _decodeCurve(prefs.getString(_customGainsKey)) ??
          _canonicalCurve(_builtInPresetGains[_flatPresetName]!);
      _userPresets = _decodeUserPresets(prefs.getString(_userPresetsKey)) ?? [];

      if (_curveForPreset(_selectedPresetName) == null) {
        _selectedPresetName = customPresetName;
      }
    } catch (e) {
      debugPrint('[EqualizerService] Error loading settings: $e');
      _isEnabled = false;
      _selectedPresetName = _flatPresetName;
      _customCurve = _canonicalCurve(_builtInPresetGains[_flatPresetName]!);
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
        jsonEncode(_encodeCurve(_customCurve)),
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
    if (_isAndroid) {
      await androidEqualizer.setEnabled(_isEnabled);
    } else if (_isDarwin) {
      await darwinEqualizer.setEnabled(_isEnabled);
    }
  }

  Future<void> _setDeviceBandGain(int bandIndex, double gainDb) async {
    if (_isAndroid) {
      final params = _androidParameters;
      if (params == null) return;
      await params.bands[bandIndex].setGain(gainDb);
    } else if (_isDarwin) {
      await darwinEqualizer.parameters.bands[bandIndex].setGain(gainDb);
    }
  }

  /// No-op until the device parameters are known; on Android
  /// [_watchAndroidParameters] re-applies the active curve as soon as they
  /// arrive.
  Future<void> _applyCurveToDevice(List<_EqualizerPoint> curve) async {
    final params = _parameters;
    if (params == null) return;

    final gains = <double>[];
    for (var i = 0; i < params.bandCount; i++) {
      final gain = _clampGain(
        _interpolateGain(curve, params.bandFrequencies[i]),
        params,
      );
      await _setDeviceBandGain(i, gain);
      gains.add(gain);
    }
    _currentBandGains = gains;
  }

  List<_EqualizerPoint> get _activeCurve =>
      _curveForPreset(_selectedPresetName) ?? _customCurve;

  List<_EqualizerPoint>? _curveForPreset(String name) {
    if (name == customPresetName) return _customCurve;

    final builtInGains = _builtInPresetGains[name];
    if (builtInGains != null) {
      return _canonicalCurve(builtInGains);
    }

    for (final userPreset in _userPresets) {
      if (userPreset.name == name) return userPreset.curve;
    }
    return null;
  }

  double _clampGain(double gain, EqParameters params) {
    return gain.clamp(params.minDecibels, params.maxDecibels).toDouble();
  }

  List<_EqualizerPoint> _currentDeviceCurve(EqParameters params) {
    return [
      for (var i = 0; i < params.bandCount; i++)
        _EqualizerPoint(
          params.bandFrequencies[i],
          i < _currentBandGains.length ? _currentBandGains[i] : 0,
        ),
    ];
  }

  static List<_EqualizerPoint> _canonicalCurve(List<double> gains) {
    return [
      for (var i = 0; i < _canonicalFrequencies.length; i++)
        _EqualizerPoint(_canonicalFrequencies[i], gains[i]),
    ];
  }

  static double _interpolateGain(List<_EqualizerPoint> curve, double hz) {
    final points = _normalizeCurve(curve);
    if (points.isEmpty) return 0;
    if (points.length == 1 || hz <= points.first.hz) return points.first.db;
    if (hz >= points.last.hz) return points.last.db;

    final target = math.log(hz);
    for (var i = 0; i < points.length - 1; i++) {
      final lower = points[i];
      final upper = points[i + 1];
      if (hz < lower.hz || hz > upper.hz) continue;

      final lowerLog = math.log(lower.hz);
      final upperLog = math.log(upper.hz);
      if (lowerLog == upperLog) return lower.db;

      final ratio = (target - lowerLog) / (upperLog - lowerLog);
      return lower.db + ((upper.db - lower.db) * ratio);
    }

    return points.last.db;
  }

  static List<_EqualizerPoint> _normalizeCurve(List<_EqualizerPoint> curve) {
    final pointsByFrequency = <double, double>{};
    for (final point in curve) {
      if (point.hz.isFinite && point.hz > 0 && point.db.isFinite) {
        pointsByFrequency[point.hz] = point.db;
      }
    }

    final points = pointsByFrequency.entries
        .map((entry) => _EqualizerPoint(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.hz.compareTo(b.hz));
    return points;
  }

  static List<Map<String, double>> _encodeCurve(
    List<_EqualizerPoint> curve,
  ) {
    return [
      for (final point in _normalizeCurve(curve))
        {
          'hz': point.hz,
          'db': point.db,
        },
    ];
  }

  static List<_EqualizerPoint>? _decodeCurve(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return null;

      final points = <_EqualizerPoint>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final hz = item['hz'];
        final db = item['db'];
        if (hz is num && db is num) {
          points.add(_EqualizerPoint(hz.toDouble(), db.toDouble()));
        }
      }

      final normalized = _normalizeCurve(points);
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  static List<_UserEqualizerPreset>? _decodeUserPresets(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return null;

      final presets = <_UserEqualizerPreset>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'];
        final gains = item['gains'];
        if (name is! String || gains == null) continue;

        final curve = _decodeCurve(jsonEncode(gains));
        if (curve == null) continue;
        presets.add(_UserEqualizerPreset(name, curve));
      }
      return presets;
    } catch (_) {
      return null;
    }
  }
}

class _EqualizerPoint {
  const _EqualizerPoint(this.hz, this.db);

  final double hz;
  final double db;
}

class _UserEqualizerPreset {
  const _UserEqualizerPreset(this.name, this.curve);

  final String name;
  final List<_EqualizerPoint> curve;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gains': EqualizerService._encodeCurve(curve),
    };
  }
}
