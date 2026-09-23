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

/// Picks up to two supporting artwork colours to glow alongside [seed] in the
/// ambient backdrop, so cover-art themes carry the artwork's whole palette
/// rather than a single hue.
///
/// Swatches are ranked like [selectDynamicThemeSeed], but each pick must be
/// visibly different (hue or lightness) from the colours already chosen, so a
/// cover dominated by one hue doesn't repeat it three times.
List<Color> selectAmbientColors(
  Iterable<({Color color, int population})> swatches,
  Color seed,
) {
  final candidates = swatches.where((swatch) => swatch.population > 0).toList();
  if (candidates.isEmpty) return <Color>[seed];
  final largestPopulation =
      candidates.map((swatch) => swatch.population).reduce(math.max).toDouble();

  double score(({Color color, int population}) swatch) {
    final hsl = HSLColor.fromColor(swatch.color);
    final population = math.sqrt(swatch.population / largestPopulation);
    // Saturation matters more here than for the seed: a glow is only worth
    // painting if it adds colour.
    return population * (0.15 + 0.85 * hsl.saturation);
  }

  bool distinct(Color a, Color b) {
    final ha = HSLColor.fromColor(a);
    final hb = HSLColor.fromColor(b);
    final hueGap = (ha.hue - hb.hue).abs();
    final hueDistance = math.min(hueGap, 360 - hueGap);
    final colourful = ha.saturation > 0.18 && hb.saturation > 0.18;
    return (colourful && hueDistance > 24) ||
        (ha.lightness - hb.lightness).abs() > 0.28;
  }

  final ranked = [...candidates]..sort((a, b) => score(b).compareTo(score(a)));
  final picked = <Color>[seed];
  for (final swatch in ranked) {
    if (picked.length == 3) break;
    if (picked.every((c) => distinct(c, swatch.color))) {
      picked.add(swatch.color);
    }
  }
  return picked;
}
