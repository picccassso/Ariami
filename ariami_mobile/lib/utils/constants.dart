import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Semantic surface + muted-text palette resolved from the active theme, so
/// widgets follow the current brightness / colour-source rather than hardcoding
/// values.
@immutable
class PlayerColors extends ThemeExtension<PlayerColors> {
  const PlayerColors({
    required this.base,
    required this.baseB,
    required this.panel,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceHover,
    required this.popover,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.band,
    required this.fill,
    required this.glowA,
    required this.glowB,
    required this.glowC,
  });

  /// The screen's ground — the duotone's first ink, top-left.
  final Color base;

  /// The duotone's second ink: the ground blends from [base] at the top-left
  /// into this at the bottom-right (see [groundGradient]). Equal to [base] in
  /// the neutral themes, which stay one flat colour.
  final Color baseB;

  /// The fill of panels and cards. Transparent: the app is one flat
  /// surface, divided by [border] rules, not boxes.
  final Color panel;

  /// An opaque stand-in for the ground — rings and badges that must mask
  /// what's beneath them while still reading as "the ground colour".
  final Color surface;

  /// A raised surface on the ground — search and text fields.
  final Color surfaceHigh;

  /// Translucent hover / pressed wash.
  final Color surfaceHover;

  /// Opaque, elevated background for menus, dialogs and floating bars that
  /// sit over content.
  final Color popover;

  /// Hairline rules between columns and rows, and outlines.
  final Color border;

  /// Primary on-surface text / icons (the ink).
  final Color textPrimary;

  /// Muted secondary text.
  final Color textSecondary;

  /// The mini player's own ground, a step off [base].
  final Color band;

  /// The mini player's progress fill: a brighter print of the sleeve tone
  /// that sweeps across it as a song plays.
  final Color fill;

  /// Glow colours for the full-screen player's backdrop and the music
  /// visualizer, strongest first.
  final Color glowA;
  final Color glowB;
  final Color glowC;

  static const PlayerColors dark = PlayerColors(
    base: Color(0xFF1C1D20),
    baseB: Color(0xFF1C1D20),
    panel: Color(0x00000000),
    surface: Color(0xFF1C1D20),
    surfaceHigh: Color(0xFF27292D),
    surfaceHover: Color(0x10E8E8E4),
    popover: Color(0xFF2A2C30),
    border: Color(0xFF34363B),
    textPrimary: Color(0xFFE8E8E4),
    textSecondary: Color(0xFF8D8F95),
    band: Color(0xFF222327),
    fill: Color(0xFF3A3C41),
    glowA: Color(0xFF3A3A42),
    glowB: Color(0xFF2A2A30),
    glowC: Color(0xFF1F1F24),
  );

  static const PlayerColors light = PlayerColors(
    base: Color(0xFFEBECE8),
    baseB: Color(0xFFEBECE8),
    panel: Color(0x00000000),
    surface: Color(0xFFEBECE8),
    surfaceHigh: Color(0xFFDFE0DB),
    surfaceHover: Color(0x0D1B1C1F),
    popover: Color(0xFFF6F6F3),
    border: Color(0xFFCDCEC9),
    textPrimary: Color(0xFF1B1C1F),
    textSecondary: Color(0xFF5D5F64),
    band: Color(0xFFE2E3DE),
    fill: Color(0xFFC6C7C1),
    glowA: Color(0xFFFFFFFF),
    glowB: Color(0xFFD6D6DE),
    glowC: Color(0xFFF4F4F7),
  );

  /// The sleeve palette for colour-source themes, printed in the cover's
  /// colours like a two-ink sleeve: [seed] is the first ink (the ground's
  /// top-left and every raised surface), the cover's second colour the
  /// second ink the ground blends into, and its third the mini player's
  /// [fill]. [ambient] is the cover's palette, seed first; without one (a
  /// preset or custom colour) the seed's neighbouring hues stand in.
  ///
  /// A near-grey seed (a black-and-white cover) falls back to graphite, so it
  /// never comes out as a muddy tint.
  factory PlayerColors.fromSeed(Color seed, {List<Color>? ambient}) {
    final glows = ambientGlows(seed, ambient);
    final hsl = HSLColor.fromColor(seed);
    if (hsl.saturation < 0.1) {
      return dark.copyWith(glowA: glows[0], glowB: glows[1], glowC: glows[2]);
    }
    final inks = <HSLColor>[
      for (final c in ambient ?? const <Color>[]) HSLColor.fromColor(c),
    ];
    HSLColor ink(int i, HSLColor fallback) =>
        i < inks.length && inks[i].saturation >= 0.1 ? inks[i] : fallback;
    final second = ink(1, hsl.withHue((hsl.hue + 38) % 360));
    final third = ink(2, hsl);

    // Both inks are printed at the same depth, so the blend between them
    // reads as a change of colour rather than of shade, and carry most of
    // the cover's own saturation. White text keeps over 10:1 contrast.
    Color deep(HSLColor c, double l) => c
        .withSaturation(c.saturation.clamp(0.0, 0.65) * 0.85)
        .withLightness(l)
        .toColor();
    Color ground(double l) => deep(hsl, l);
    const ink0 = Color(0xFFF0F1F4);
    return PlayerColors(
      base: ground(0.15),
      baseB: deep(second, 0.15),
      panel: const Color(0x00000000),
      surface: ground(0.15),
      surfaceHigh: ground(0.2),
      surfaceHover: ink0.withValues(alpha: 0.07),
      popover: ground(0.21),
      border: ink0.withValues(alpha: 0.11),
      textPrimary: ink0,
      textSecondary: ink0.withValues(alpha: 0.68),
      // The bar sits where the ground has blended into the second ink.
      band: deep(second, 0.18),
      fill: third
          .withSaturation(third.saturation.clamp(0.35, 0.65))
          .withLightness(0.34)
          .toColor(),
      glowA: glows[0],
      glowB: glows[1],
      glowC: glows[2],
    );
  }

  /// The screen's ground: [base] blending into [baseB] corner to corner.
  LinearGradient get groundGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [base, baseB],
      );

  /// Three glow colours for the ambient backdrop: [ambient] swatches when
  /// supplied (normalised to a luminous mid-tone), padded with the seed's
  /// analogous hues.
  static List<Color> ambientGlows(Color seed, List<Color>? ambient) {
    final seedHsl = HSLColor.fromColor(seed);
    Color glow(HSLColor c) => c
        .withSaturation(
            c.saturation < 0.1 ? c.saturation : c.saturation.clamp(0.45, 0.95))
        .withLightness(c.lightness.clamp(0.36, 0.52))
        .toColor();
    final derived = <HSLColor>[
      seedHsl,
      seedHsl.withHue((seedHsl.hue + 38) % 360),
      seedHsl.withHue((seedHsl.hue + 322) % 360),
    ];
    final sources = <HSLColor>[
      for (final c in ambient ?? const <Color>[]) HSLColor.fromColor(c),
    ];
    return [
      for (var i = 0; i < 3; i++)
        glow(i < sources.length ? sources[i] : derived[i]),
    ];
  }

  @override
  PlayerColors copyWith({
    Color? base,
    Color? baseB,
    Color? panel,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceHover,
    Color? popover,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? band,
    Color? fill,
    Color? glowA,
    Color? glowB,
    Color? glowC,
  }) {
    return PlayerColors(
      base: base ?? this.base,
      baseB: baseB ?? this.baseB,
      panel: panel ?? this.panel,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      popover: popover ?? this.popover,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      band: band ?? this.band,
      fill: fill ?? this.fill,
      glowA: glowA ?? this.glowA,
      glowB: glowB ?? this.glowB,
      glowC: glowC ?? this.glowC,
    );
  }

  @override
  PlayerColors lerp(PlayerColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PlayerColors(
      base: l(base, other.base),
      baseB: l(baseB, other.baseB),
      panel: l(panel, other.panel),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      popover: l(popover, other.popover),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      band: l(band, other.band),
      fill: l(fill, other.fill),
      glowA: l(glowA, other.glowA),
      glowB: l(glowB, other.glowB),
      glowC: l(glowC, other.glowC),
    );
  }
}

extension PlayerColorsContext on BuildContext {
  PlayerColors get colors =>
      Theme.of(this).extension<PlayerColors>() ?? PlayerColors.dark;
}

class AppTheme {
  /// Archivo in three widths, shared with Premium Desktop: regular for
  /// reading, condensed for headings and extra condensed for display titles,
  /// the way record sleeves and spines set long titles without truncating.
  static const String bodyFamily = 'Archivo';
  static const String headingFamily = 'Archivo Condensed';
  static const String displayFamily = 'Archivo Extra Condensed';

  /// Corner radii, by hierarchy rather than one value for everything:
  /// covers are crisp like a printed sleeve, controls slightly softened,
  /// floating surfaces (dialogs, sheets) a little more.
  static const double coverRadius = 2;
  static const double cardRadius = 4;
  static const double tileRadius = 6;
  static const double panelRadius = 10;

  /// A display title (album, now playing): extra condensed, tight leading.
  static TextStyle display(double size, {Color? color}) => TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 0.9,
        letterSpacing: -0.01 * size,
        color: color,
      );

  /// A section heading ("Playlists"): condensed, semi-bold.
  static TextStyle heading(double size, {Color? color}) => TextStyle(
        fontFamily: headingFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: color,
      );

  /// Times and counts: tabular figures so columns of numbers line up.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Page transitions for the *nested* tab navigators.
  static const PageTransitionsTheme nestedNavigatorPageTransitions =
      PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static ThemeData buildNeutralTheme({required Brightness brightness}) =>
      _buildBaseTheme(
        brightness: brightness,
        colors: brightness == Brightness.dark
            ? PlayerColors.dark
            : PlayerColors.light,
      );

  /// The pre-connection surfaces: graphite lit in the app icon's navy.
  static ThemeData setup() {
    return _buildBaseTheme(
      brightness: Brightness.dark,
      colors: PlayerColors.dark.copyWith(
        glowA: const Color(0xFF2B4C9B),
        glowB: const Color(0xFF3A2C86),
        glowC: const Color(0xFF155E75),
      ),
    );
  }

  /// A dark theme printed in [seedColor]'s tone. [ambient] supplies the
  /// cover's other colours for the duotone and the full player's glow.
  static ThemeData buildColorSourceTheme({
    required Color seedColor,
    List<Color>? ambient,
  }) =>
      _buildBaseTheme(
        brightness: Brightness.dark,
        colors: PlayerColors.fromSeed(seedColor, ambient: ambient),
      );

  static ThemeData _buildBaseTheme({
    required Brightness brightness,
    required PlayerColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    // No accent: the primary colour is the ink itself, so a selected switch
    // or a filled button reads as ink on ground, inverted.
    final primary = colors.textPrimary;
    final onPrimary = colors.base;
    final systemOverlayStyle = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          );

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: colors.base,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.popover,
      error: const Color(0xFFFF6B6B),
      onError: Colors.white,
    );

    final popoverShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: colors.border),
    );
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(tileRadius)),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tileRadius),
      borderSide: BorderSide.none,
    );

    final baseTypography =
        isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    TextStyle? displayStyle(TextStyle? style) => style?.copyWith(
          fontFamily: displayFamily,
          fontWeight: FontWeight.w600,
          height: 0.95,
          letterSpacing: -0.4,
        );
    TextStyle? headingStyle(TextStyle? style) => style?.copyWith(
          fontFamily: headingFamily,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: bodyFamily,
      scaffoldBackgroundColor: colors.base,
      primaryColor: primary,
      canvasColor: colors.base,
      dividerColor: colors.border,
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      extensions: <ThemeExtension<dynamic>>[colors],
      colorScheme: colorScheme,
      // No ripple: a pressed row or button takes the same flat wash desktop
      // uses for hover, so a tap still registers without the ink splash.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: colors.surfaceHover,

      textTheme: baseTypography
          .apply(fontFamily: bodyFamily)
          .copyWith(
            displayLarge: displayStyle(baseTypography.displayLarge),
            displayMedium: displayStyle(baseTypography.displayMedium),
            displaySmall: displayStyle(baseTypography.displaySmall),
            headlineLarge: displayStyle(baseTypography.headlineLarge),
            headlineMedium: headingStyle(baseTypography.headlineMedium),
            headlineSmall: headingStyle(baseTypography.headlineSmall),
            titleLarge: headingStyle(baseTypography.titleLarge),
            bodyMedium: TextStyle(
                fontFamily: bodyFamily,
                color: colors.textSecondary,
                fontSize: 13.5),
            labelLarge: TextStyle(
                fontFamily: bodyFamily,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600),
          )
          .apply(
            bodyColor: colors.textPrimary,
            displayColor: colors.textPrimary,
          ),

      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (BuildContext context) =>
            const Icon(LucideIcons.chevronLeft, size: 20),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemOverlayStyle,
        titleTextStyle: TextStyle(
          fontFamily: headingFamily,
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: colors.textPrimary,
        unselectedItemColor: colors.textSecondary,
        elevation: 0,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: colors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: popoverShape,
        textStyle: TextStyle(
            fontFamily: bodyFamily, color: colors.textPrimary, fontSize: 13.5),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.popover),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(popoverShape),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius),
          side: BorderSide(color: colors.border),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.popover,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(panelRadius)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.popover,
        contentTextStyle: TextStyle(
          fontFamily: bodyFamily,
          color: colors.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: primary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          side: BorderSide(color: colors.border),
        ),
      ),

      cardTheme: CardThemeData(
        color: colors.surfaceHigh,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          side: BorderSide(color: colors.border),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minVerticalPadding: 8,
      ),

      iconTheme: IconThemeData(color: colors.textPrimary, size: 24),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        shape: const CircleBorder(),
        elevation: 0,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: colors.border,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 3,
        borderRadius: BorderRadius.circular(2),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? onPrimary
                : colors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primary
                : colors.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.transparent
                : colors.border),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: primary,
        side: BorderSide(color: colors.border),
        shape: controlShape,
        labelStyle: TextStyle(
            fontFamily: bodyFamily, color: colors.textPrimary, fontSize: 13),
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: primary,
        inactiveTrackColor: colors.border,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.08),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          shape: controlShape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: bodyFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: controlShape,
          textStyle: const TextStyle(
              fontFamily: bodyFamily, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.textPrimary,
          shape: controlShape,
          textStyle: const TextStyle(
              fontFamily: bodyFamily, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          shape: controlShape,
          textStyle: const TextStyle(
              fontFamily: bodyFamily, fontWeight: FontWeight.w500),
        ),
      ),
      segmentedButtonTheme: const SegmentedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(controlShape)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceHigh,
        labelStyle: TextStyle(color: colors.textSecondary),
        hintStyle: TextStyle(color: colors.textSecondary),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.25),
        selectionHandleColor: primary,
      ),
    );
  }

  static ThemeData get lightTheme =>
      buildNeutralTheme(brightness: Brightness.light);
  static ThemeData get darkTheme =>
      buildNeutralTheme(brightness: Brightness.dark);
}
