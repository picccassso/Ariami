import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Chooses a representative artwork colour for whole-player theming.
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
/// Swatches are ranked by population weighted toward saturation (a different
/// formula from [selectDynamicThemeSeed]), and each pick must be visibly
/// different (hue or lightness) from the colours already chosen, so a cover
/// dominated by one hue doesn't repeat it three times.
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

  final ranked = [...candidates]..sort((a, b) => score(b).compareTo(score(a)));
  final picked = <Color>[seed];
  for (final swatch in ranked) {
    if (picked.length == 3) break;
    if (picked.every((c) => _distinct(c, swatch.color, lightnessGap: 0.28))) {
      picked.add(swatch.color);
    }
  }
  return picked;
}

/// The artwork's own three main colours, for the music visualizer.
///
/// Ranked by how much of the cover each fills, with colour only breaking
/// near-ties, and each visibly different from those already chosen; small
/// details (well under a tenth of the main colour's area) don't count. They
/// are only lightened or darkened enough to glow, never resaturated or
/// hue-shifted, and a cover with fewer distinct colours repeats its main one
/// lighter and darker rather than inventing hues. Empty without swatches.
List<Color> selectArtworkColors(
  Iterable<({Color color, int population})> swatches,
) {
  final candidates = swatches.where((swatch) => swatch.population > 0).toList();
  if (candidates.isEmpty) return const <Color>[];
  final largestPopulation =
      candidates.map((swatch) => swatch.population).reduce(math.max).toDouble();

  double score(({Color color, int population}) swatch) =>
      math.sqrt(swatch.population / largestPopulation) *
      (0.55 + 0.45 * HSLColor.fromColor(swatch.color).saturation);

  final ranked = [...candidates]..sort((a, b) => score(b).compareTo(score(a)));
  final smallest = 0.3 * score(ranked.first);
  final picked = <HSLColor>[];
  for (final swatch in ranked) {
    if (picked.length == 3 || score(swatch) < smallest) break;
    if (picked.every(
      (c) => _distinct(c.toColor(), swatch.color, lightnessGap: 0.2),
    )) {
      final hsl = HSLColor.fromColor(swatch.color);
      picked.add(hsl.withLightness(hsl.lightness.clamp(0.24, 0.5)));
    }
  }
  final main = picked.first;
  const shades = [0.14, -0.12];
  while (picked.length < 3) {
    final shade = shades[picked.length - 1];
    picked.add(main.withLightness((main.lightness + shade).clamp(0.2, 0.7)));
  }
  return [for (final c in picked) c.toColor()];
}

/// Whether [a] and [b] read as different colours: apart in hue (when both
/// have colour to speak of) or in lightness by more than [lightnessGap].
bool _distinct(Color a, Color b, {required double lightnessGap}) {
  final ha = HSLColor.fromColor(a);
  final hb = HSLColor.fromColor(b);
  final hueGap = (ha.hue - hb.hue).abs();
  final hueDistance = math.min(hueGap, 360 - hueGap);
  final colourful = ha.saturation > 0.18 && hb.saturation > 0.18;
  return (colourful && hueDistance > 24) ||
      (ha.lightness - hb.lightness).abs() > lightnessGap;
}
