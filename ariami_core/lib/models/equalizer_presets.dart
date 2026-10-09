/// Shared equalizer data: built-in presets, band layout and the pure curve
/// maths / JSON helpers used by the mobile and desktop equalizer services.
library;

import 'dart:convert';
import 'dart:math' as math;

/// Unified view of the device equalizer's capabilities, independent of the
/// platform effect backing it.
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

const List<double> equalizerCanonicalFrequencies = [
  60,
  230,
  910,
  3600,
  14000,
];

const Map<String, List<double>> equalizerBuiltInPresetGains = {
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

List<EqualizerPoint> canonicalEqualizerCurve(List<double> gains) {
  return [
    for (var i = 0; i < equalizerCanonicalFrequencies.length; i++)
      EqualizerPoint(equalizerCanonicalFrequencies[i], gains[i]),
  ];
}

double interpolateEqualizerGain(List<EqualizerPoint> curve, double hz) {
  final points = normalizeEqualizerCurve(curve);
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

List<EqualizerPoint> normalizeEqualizerCurve(List<EqualizerPoint> curve) {
  final pointsByFrequency = <double, double>{};
  for (final point in curve) {
    if (point.hz.isFinite && point.hz > 0 && point.db.isFinite) {
      pointsByFrequency[point.hz] = point.db;
    }
  }

  final points = pointsByFrequency.entries
      .map((entry) => EqualizerPoint(entry.key, entry.value))
      .toList()
    ..sort((a, b) => a.hz.compareTo(b.hz));
  return points;
}

List<Map<String, double>> encodeEqualizerCurve(
  List<EqualizerPoint> curve,
) {
  return [
    for (final point in normalizeEqualizerCurve(curve))
      {
        'hz': point.hz,
        'db': point.db,
      },
  ];
}

List<EqualizerPoint>? decodeEqualizerCurve(String? jsonString) {
  if (jsonString == null || jsonString.isEmpty) return null;

  try {
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) return null;

    final points = <EqualizerPoint>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final hz = item['hz'];
      final db = item['db'];
      if (hz is num && db is num) {
        points.add(EqualizerPoint(hz.toDouble(), db.toDouble()));
      }
    }

    final normalized = normalizeEqualizerCurve(points);
    return normalized.isEmpty ? null : normalized;
  } catch (_) {
    return null;
  }
}

List<UserEqualizerPreset>? decodeUserEqualizerPresets(String? jsonString) {
  if (jsonString == null || jsonString.isEmpty) return null;

  try {
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) return null;

    final presets = <UserEqualizerPreset>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name'];
      final gains = item['gains'];
      if (name is! String || gains == null) continue;

      final curve = decodeEqualizerCurve(jsonEncode(gains));
      if (curve == null) continue;
      presets.add(UserEqualizerPreset(name, curve));
    }
    return presets;
  } catch (_) {
    return null;
  }
}

class EqualizerPoint {
  const EqualizerPoint(this.hz, this.db);

  final double hz;
  final double db;
}

class UserEqualizerPreset {
  const UserEqualizerPreset(this.name, this.curve);

  final String name;
  final List<EqualizerPoint> curve;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'gains': encodeEqualizerCurve(curve),
    };
  }
}
