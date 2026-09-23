import 'package:ariami_mobile/utils/dynamic_theme_seed.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectDynamicThemeSeed', () {
    test('lets a substantial colourful cluster beat a neutral background', () {
      const vibrant = Color(0xFF1565C0);

      final seed = selectDynamicThemeSeed([
        (color: const Color(0xFF777777), population: 1000),
        (color: vibrant, population: 200),
      ]);

      expect(seed, vibrant);
    });

    test('tiny amber accents cannot overpower representative deep reds', () {
      const representativeRed = Color(0xFF30090D);

      final seed = selectDynamicThemeSeed([
        (color: representativeRed, population: 128303),
        (color: const Color(0xFF921010), population: 63619),
        (color: const Color(0xFFEBB339), population: 4322),
      ]);

      final seedHsl = HSLColor.fromColor(seed!);
      final redHsl = HSLColor.fromColor(representativeRed);
      expect(seedHsl.hue, closeTo(redHsl.hue, 0.5));
      expect(seedHsl.saturation, closeTo(redHsl.saturation, 0.01));
    });

    test('preserves a greyscale cover instead of manufacturing saturation', () {
      const grey = Color(0xFF777777);

      final seed = selectDynamicThemeSeed([
        (color: grey, population: 1000),
        (color: const Color(0xFF999999), population: 300),
      ]);
      final hsl = HSLColor.fromColor(seed!);

      expect(hsl.saturation, closeTo(0, 0.001));
    });

    test('pulls only extreme lightness into the usable theme band', () {
      final dark = selectDynamicThemeSeed([
        (color: const Color(0xFF050505), population: 100),
      ]);
      final light = selectDynamicThemeSeed([
        (color: const Color(0xFFFAFAFA), population: 100),
      ]);

      expect(HSLColor.fromColor(dark!).lightness, closeTo(0.30, 0.01));
      expect(HSLColor.fromColor(light!).lightness, closeTo(0.70, 0.01));
    });

    test('returns null when artwork has no usable palette swatch', () {
      expect(selectDynamicThemeSeed(const []), isNull);
    });
  });

  group('selectAmbientColors', () {
    test('ambient glows add distinct artwork colours after the seed', () {
      const seed = Color(0xFF921010);
      final glows = selectAmbientColors([
        (color: seed, population: 60000),
        // Same hue and tone as the seed: must not be repeated as a glow.
        (color: const Color(0xFF8A1414), population: 50000),
        (color: const Color(0xFF1E3FA8), population: 9000),
        (color: const Color(0xFFE0B040), population: 4000),
      ], seed);

      expect(glows, [seed, const Color(0xFF1E3FA8), const Color(0xFFE0B040)]);
    });

    test('returns only seed when swatches are empty', () {
      const seed = Color(0xFF123456);
      expect(selectAmbientColors(const [], seed), [seed]);
    });
  });
}
