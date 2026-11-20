import 'package:flutter/material.dart';

/// Theme builders + semantic surface palette for the music player.
///
/// Two flavours, mirroring the mobile app's appearance model:
///  * neutral (graphite / paper) themes for light / dark / system, and
///  * colour-source themes seeded from a preset, custom or cover-art colour.
///
/// The player is flat panels, not glass over a glow: the cover art is the
/// only imagery and the only source of colour. Colour-source themes print the
/// cover's colours like a two-ink sleeve ([PlayerColors.fromSeed]): the ground
/// blends from its main colour into its second, and the transport bar fills
/// with a third ([PlayerColors.fill]) as a song plays. There is no accent colour: active states invert ink
/// and ground. Widgets read all of this via `context.colors`.
class PlayerTheme {
  PlayerTheme._();

  // Legacy dark constants, kept for the pre-player splash and as a safe default
  // for [PlayerColorsContext.colors] outside a themed subtree.
  static const Color black = Color(0xFF000000);
  static const Color base = Color(0xFF1C1D20);
  static const Color surface = Color(0xFF1C1D20);
  static const Color surfaceHigh = Color(0xFF27292D);
  static const Color surfaceHover = Color(0xFF2E3034);
  static const Color border = Color(0xFF34363B);
  static const Color textPrimary = Color(0xFFE8E8E4);
  static const Color textSecondary = Color(0xFF8D8F95);
  static const Color accent = Color(0xFF1DB954); // legacy preset default

  /// Archivo in three widths: regular for reading, condensed for headings
  /// and extra condensed for display titles, the way record sleeves and
  /// spines set long titles without truncating them.
  static const String bodyFamily = 'Archivo';
  static const String headingFamily = 'Archivo Condensed';
  static const String displayFamily = 'Archivo Extra Condensed';

  /// Corner radii, by hierarchy rather than one value for everything:
  /// covers are crisp like a printed sleeve, controls slightly softened,
  /// floating surfaces (dialogs, menus) a little more.
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

  /// A section heading ("Recently played"): condensed, semi-bold.
  static TextStyle heading(double size, {Color? color}) => TextStyle(
        fontFamily: headingFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: color,
      );

  /// Times and counts: tabular figures so columns of numbers line up.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static ThemeData neutral({
    required Brightness brightness,
    bool amoled = false,
  }) {
    final isDark = brightness == Brightness.dark;
    return _build(
      brightness: brightness,
      colors: isDark
          ? (amoled ? PlayerColors.amoled : PlayerColors.dark)
          : PlayerColors.light,
    );
  }

  /// The setup and pre-connection surfaces (onboarding, connect, sign in,
  /// register, and the app-wide default): always the neutral dark theme,
  /// whatever appearance the player is set to.
  static ThemeData setup() => neutral(brightness: Brightness.dark);

  /// A dark theme printed in [seed]'s tone. [ambient] supplies the glow
  /// colours the full-screen player's backdrop and visualizer use (e.g.
  /// several artwork swatches); when omitted they come from the seed.
  static ThemeData colorSource(
    Color seed, {
    List<Color>? ambient,
    bool amoled = false,
  }) =>
      _build(
        brightness: Brightness.dark,
        colors: PlayerColors.fromSeed(seed, ambient: ambient, amoled: amoled),
      );

  static ThemeData _build({
    required Brightness brightness,
    required PlayerColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    // No accent: the primary colour is the ink itself, so a selected switch
    // or a filled button reads as ink on ground, inverted.
    final primary = colors.textPrimary;
    final onPrimary = colors.base;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.popover,
      error: const Color(0xFFFF6B6B),
      onError: Colors.white,
    );

    final baseTypography =
        isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    final popoverShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: colors.border),
    );
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(tileRadius)),
    );

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
      colorScheme: colorScheme,
      canvasColor: colors.base,
      dividerColor: colors.border,
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      // Setup steps and the server dashboard: a quiet, centred title rather
      // than Material's large left-aligned headline.
      appBarTheme: AppBarTheme(
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: headingFamily,
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
      splashFactory: NoSplash.splashFactory,
      hoverColor: colors.surfaceHover,
      highlightColor: colors.surfaceHover,
      iconTheme: IconThemeData(color: colors.textPrimary),
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
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF34363B) : const Color(0xFF1B1C1F),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(
          fontFamily: bodyFamily,
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(panelRadius)),
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
        secondarySelectedColor: primary,
        checkmarkColor: onPrimary,
        side: BorderSide(color: colors.border),
        shape: controlShape,
        labelStyle: TextStyle(
          fontFamily: bodyFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onPrimary;
            if (states.contains(WidgetState.disabled)) {
              return colors.textSecondary;
            }
            return colors.textPrimary;
          }),
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: bodyFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onPrimary,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: primary,
        inactiveTrackColor: colors.border,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.08),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        mouseCursor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(3),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor:
            WidgetStatePropertyAll(colors.textPrimary.withValues(alpha: 0.18)),
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
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: controlShape,
          textStyle: const TextStyle(
              fontFamily: bodyFamily, fontWeight: FontWeight.w600),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.textPrimary,
          shape: controlShape,
          textStyle: const TextStyle(
              fontFamily: bodyFamily, fontWeight: FontWeight.w500),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          shape: controlShape,
          textStyle: const TextStyle(
              fontFamily: bodyFamily, fontWeight: FontWeight.w500),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: controlShape,
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(controlShape),
          mouseCursor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      // Cards are used by the embedded server dashboard (InfoCard, tables).
      cardTheme: CardThemeData(
        color: colors.surfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceHigh,
        hintStyle: TextStyle(color: colors.textSecondary),
        // Underline (not outline) so a floating label lands inside the filled
        // field; an outline border floats it onto the top edge, which reads
        // as detached once the border itself is invisible.
        border: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide.none,
        ),
        // No contentPadding override: labelled fields need headroom for the
        // floated label, unlabelled ones want their text centred, and only
        // Flutter's per-field default gets both right.
      ),
    );
  }
}

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

  /// The window's ground — the duotone's first ink, top-left.
  final Color base;

  /// The duotone's second ink: the ground blends from [base] at the top-left
  /// into this at the bottom-right (see [groundGradient]). Equal to [base] in
  /// the neutral themes, which stay one flat colour.
  final Color baseB;

  /// The fill of the shell's columns (sidebar, content, queue). Transparent:
  /// the shell is one flat surface, divided by [border] rules, not boxes.
  final Color panel;

  /// An opaque stand-in for the ground — rings and badges that must mask
  /// what's beneath them while still reading as "the ground colour".
  final Color surface;

  /// A raised surface on the ground — search field, settings cards.
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

  /// The transport bar's own ground, a step off [base].
  final Color band;

  /// The transport bar's progress fill: a brighter print of the sleeve tone
  /// that sweeps across the bar as a song plays.
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

  static const PlayerColors amoled = PlayerColors(
    base: Color(0xFF000000),
    baseB: Color(0xFF000000),
    panel: Color(0x00000000),
    surface: Color(0xFF000000),
    surfaceHigh: Color(0xFF111214),
    surfaceHover: Color(0x14E8E8E4),
    popover: Color(0xFF141518),
    border: Color(0xFF232529),
    textPrimary: Color(0xFFE8E8E4),
    textSecondary: Color(0xFF8D8F95),
    band: Color(0xFF000000),
    fill: Color(0xFF26282C),
    glowA: Color(0xFF2E2E36),
    glowB: Color(0xFF1E1E24),
    glowC: Color(0xFF121216),
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
  /// second ink the ground blends into, and its third the transport's
  /// [fill]. [ambient] is the cover's palette, seed first; without one (a
  /// preset or custom colour) the seed's neighbouring hues stand in.
  ///
  /// A near-grey seed (a black-and-white cover) falls back to graphite, so it
  /// never comes out as a muddy tint.
  factory PlayerColors.fromSeed(
    Color seed, {
    List<Color>? ambient,
    bool amoled = false,
  }) {
    final glows = ambientGlows(seed, ambient);
    final hsl = HSLColor.fromColor(seed);
    if (hsl.saturation < 0.1) {
      return (amoled ? PlayerColors.amoled : dark).copyWith(
        glowA: glows[0],
        glowB: glows[1],
        glowC: glows[2],
      );
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
      base: amoled ? PlayerTheme.black : ground(0.15),
      baseB: amoled ? PlayerTheme.black : deep(second, 0.15),
      panel: const Color(0x00000000),
      surface: amoled ? PlayerTheme.black : ground(0.15),
      surfaceHigh: ground(amoled ? 0.08 : 0.2),
      surfaceHover: ink0.withValues(alpha: 0.07),
      popover: ground(amoled ? 0.1 : 0.21),
      border: ink0.withValues(alpha: amoled ? 0.14 : 0.11),
      textPrimary: ink0,
      textSecondary: ink0.withValues(alpha: 0.68),
      // The bar sits where the ground has blended into the second ink.
      band: amoled ? PlayerTheme.black : deep(second, 0.18),
      fill: third
          .withSaturation(third.saturation.clamp(0.35, 0.65))
          .withLightness(0.34)
          .toColor(),
      glowA: glows[0],
      glowB: glows[1],
      glowC: glows[2],
    );
  }

  /// The window's ground: [base] blending into [baseB] corner to corner.
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
