import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Selects and normalizes the artwork colour used to seed a dynamic theme.
///
/// Population remains the strongest signal, while saturation gives a
/// substantial colourful cluster enough lift to beat a black/grey background.
/// Tiny accent details cannot repaint the whole interface merely because they
/// happen to match a named "vibrant" swatch.
Color? selectDynamicThemeSeed(
  Iterable<({Color color, int population})> swatches,
) {
  final candidates = swatches.where((swatch) => swatch.population > 0).toList();
  if (candidates.isEmpty) return null;

  final largestPopulation =
      candidates.map((swatch) => swatch.population).reduce(math.max).toDouble();

  ({Color color, int population})? best;
  var bestScore = -1.0;
  for (final swatch in candidates) {
    final hsl = HSLColor.fromColor(swatch.color);
    final population = math.sqrt(swatch.population / largestPopulation);
    final colorfulness = 0.30 + (0.70 * hsl.saturation);
    final distanceFromMidpoint = ((hsl.lightness - 0.5).abs() * 2).clamp(0, 1);
    final usableLightness = 0.65 + (0.35 * (1 - distanceFromMidpoint));
    final score = population * colorfulness * usableLightness;

    if (score > bestScore) {
      best = swatch;
      bestScore = score;
    }
  }

  final hsl = HSLColor.fromColor(best!.color);
  return hsl.withLightness(hsl.lightness.clamp(0.30, 0.70)).toColor();
}
