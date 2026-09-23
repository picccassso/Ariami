import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Semantic surface + glow palette resolved from the active theme.
/// Translucent glass panels and raised surfaces let the ambient backdrop
/// glow show through, while menus, dialogs and floating cards use the
/// opaque [popover] colour.
@immutable
class PlayerColors extends ThemeExtension<PlayerColors> {
  const PlayerColors({
    required this.base,
    required this.panel,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceHover,
    required this.popover,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.glowA,
    required this.glowB,
    required this.glowC,
  });

  /// The screen backdrop the ambient glow is painted onto.
  final Color base;

  /// Translucent glass for panels (mini player dock, cards).
  final Color panel;

  /// An opaque stand-in for a panel — rings and badges that must mask what's
  /// beneath them while still reading as "the panel colour".
  final Color surface;

  /// A translucent raised surface on a panel.
  final Color surfaceHigh;

  /// Translucent hover / chip background.
  final Color surfaceHover;

  /// Opaque, elevated background for menus, dialogs and floating bars.
  final Color popover;

  /// Hairline dividers and outlines.
  final Color border;

  /// Primary on-surface text / icons.
  final Color textPrimary;

  /// Muted secondary text.
  final Color textSecondary;

  /// Ambient backdrop glow colours, strongest first.
  final Color glowA;
  final Color glowB;
  final Color glowC;

  static const PlayerColors dark = PlayerColors(
    base: Color(0xFF08080A),
    panel: Color(0x0AFFFFFF),
    surface: Color(0xFF121214),
    surfaceHigh: Color(0x10FFFFFF),
    surfaceHover: Color(0x1CFFFFFF),
    popover: Color(0xFF1C1C20),
    border: Color(0x17FFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0x9EFFFFFF),
    glowA: Color(0xFF3A3A42),
    glowB: Color(0xFF2A2A30),
    glowC: Color(0xFF1F1F24),
  );

  static const PlayerColors light = PlayerColors(
    base: Color(0xFFE9E9EE),
    panel: Color(0xB8FFFFFF),
    surface: Color(0xFFF6F6F8),
    surfaceHigh: Color(0x0B000000),
    surfaceHover: Color(0x14000000),
    popover: Color(0xFFFFFFFF),
    border: Color(0x14000000),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0x94000000),
    glowA: Color(0xFFFFFFFF),
    glowB: Color(0xFFD6D6DE),
    glowC: Color(0xFFF4F4F7),
  );

  /// Tints the backdrop toward [seed] for colour-source themes: a deep,
  /// seed-hued base with luminous glows, under neutral translucent glass so
  /// the colour comes from the light behind the panels rather than from
  /// flat-painted surfaces.
  factory PlayerColors.fromSeed(Color seed, {List<Color>? ambient}) {
    final hsl = HSLColor.fromColor(seed);
    final sat = hsl.saturation;
    Color tone(double s, double l) =>
        hsl.withSaturation(s.clamp(0.0, 1.0)).withLightness(l).toColor();
    final glows = ambientGlows(seed, ambient);
    return PlayerColors(
      base: tone(sat * 0.55, 0.055),
      panel: const Color(0x0DFFFFFF),
      surface: tone(sat * 0.45, 0.10),
      surfaceHigh: const Color(0x12FFFFFF),
      surfaceHover: const Color(0x1FFFFFFF),
      popover: tone(sat * 0.38, 0.13),
      border: const Color(0x1AFFFFFF),
      textPrimary: Colors.white,
      textSecondary: const Color(0xA6FFFFFF),
      glowA: glows[0],
      glowB: glows[1],
      glowC: glows[2],
    );
  }

  /// Three glow colours for the ambient backdrop: [ambient] swatches when
  /// supplied (normalised to a luminous mid-tone), padded with the seed's
  /// neighbouring hues.
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
    Color? panel,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceHover,
    Color? popover,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? glowA,
    Color? glowB,
    Color? glowC,
  }) {
    return PlayerColors(
      base: base ?? this.base,
      panel: panel ?? this.panel,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      popover: popover ?? this.popover,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
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
      panel: l(panel, other.panel),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      popover: l(popover, other.popover),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      glowA: l(glowA, other.glowA),
      glowB: l(glowB, other.glowB),
      glowC: l(glowC, other.glowC),
    );
  }
}

typedef AppColors = PlayerColors;

extension PlayerColorsContext on BuildContext {
  PlayerColors get colors =>
      Theme.of(this).extension<PlayerColors>() ?? PlayerColors.dark;
}

class AppTheme {
  // Modern Shape
  static const double panelRadius = 20.0;
  static const double cardRadius = 14.0;
  static const double tileRadius = 10.0;

  /// Page transitions for the *nested* tab navigators.
  static const PageTransitionsTheme nestedNavigatorPageTransitions =
      PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static TextStyle? _tight(TextStyle? style, double letterSpacing) => style
      ?.copyWith(letterSpacing: letterSpacing, fontWeight: FontWeight.w800);

  static ThemeData buildNeutralTheme({
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? Colors.white : Colors.black;
    final onPrimary = isDark ? Colors.black : Colors.white;
    final colors = isDark ? PlayerColors.dark : PlayerColors.light;

    return _buildBaseTheme(
      brightness: brightness,
      colors: colors,
      primary: primary,
      onPrimary: onPrimary,
    );
  }

  /// The pre-connection surfaces: neutral dark lit in the app icon's navy.
  static ThemeData setup() {
    return _buildBaseTheme(
      brightness: Brightness.dark,
      primary: Colors.white,
      onPrimary: Colors.black,
      colors: PlayerColors.dark.copyWith(
        base: const Color(0xFF05070D),
        glowA: const Color(0xFF2B4C9B),
        glowB: const Color(0xFF3A2C86),
        glowC: const Color(0xFF155E75),
      ),
    );
  }

  static ThemeData buildColorSourceTheme({
    required Color seedColor,
    List<Color>? ambient,
  }) {
    const brightness = Brightness.dark;
    final hsl = HSLColor.fromColor(seedColor);
    final accent = hsl
        .withSaturation(hsl.saturation < 0.12
            ? hsl.saturation
            : hsl.saturation.clamp(0.55, 0.92))
        .withLightness(0.68)
        .toColor();
    final colors = PlayerColors.fromSeed(seedColor, ambient: ambient);

    return _buildBaseTheme(
      brightness: brightness,
      colors: colors,
      primary: accent,
      onPrimary: const Color(0xFF0B0B0E),
    );
  }

  // Backward-compatible builder used in player-specific theme wrappers.
  static ThemeData buildTheme({
    required Brightness brightness,
    required Color seedColor,
    List<Color>? ambient,
  }) =>
      buildColorSourceTheme(seedColor: seedColor, ambient: ambient);

  static ThemeData _buildBaseTheme({
    required Brightness brightness,
    required PlayerColors colors,
    required Color primary,
    required Color onPrimary,
  }) {
    final isDark = brightness == Brightness.dark;
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
      error: const Color(0xFFFF5A5F),
      onError: Colors.white,
    );

    final popoverShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tileRadius + 4),
      side: BorderSide(color: colors.border),
    );

    final baseTypography =
        isDark ? Typography.whiteMountainView : Typography.blackMountainView;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.base,
      primaryColor: primary,
      canvasColor: colors.base,
      dividerColor: colors.border,
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      extensions: <ThemeExtension<dynamic>>[colors],
      colorScheme: colorScheme,

      // Typography
      textTheme: baseTypography
          .apply(
            bodyColor: colors.textPrimary,
            displayColor: colors.textPrimary,
          )
          .copyWith(
            bodyMedium: TextStyle(color: colors.textSecondary, fontSize: 13),
            labelLarge: TextStyle(
                color: colors.textPrimary, fontWeight: FontWeight.w600),
            displayLarge: _tight(baseTypography.displayLarge, -1.5),
            displayMedium: _tight(baseTypography.displayMedium, -1.2),
            displaySmall: _tight(baseTypography.displaySmall, -1.0),
            headlineLarge: _tight(baseTypography.headlineLarge, -0.9),
            headlineMedium: _tight(baseTypography.headlineMedium, -0.7),
            headlineSmall: _tight(baseTypography.headlineSmall, -0.5),
            titleLarge: _tight(baseTypography.titleLarge, -0.4)
                ?.copyWith(fontWeight: FontWeight.w700),
          )
          .apply(
            bodyColor: colors.textPrimary,
            displayColor: colors.textPrimary,
          ),

      // Component Themes
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
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: popoverShape,
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 13.5),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.popover),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(popoverShape),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius + 4),
          side: BorderSide(color: colors.border),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.popover,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.popover,
        contentTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: primary,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius + 4),
          side: BorderSide(color: colors.border),
        ),
      ),

      cardTheme: CardThemeData(
        color: colors.surfaceHigh,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      iconTheme: IconThemeData(
        color: colors.textPrimary,
        size: 24,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        shape: const CircleBorder(),
        elevation: 4,
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: primary,
        inactiveTrackColor: colors.textPrimary.withValues(alpha: 0.14),
        thumbColor: colors.textPrimary,
        overlayColor: primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE9E9E9),
        labelStyle: TextStyle(color: colors.textSecondary),
        hintStyle: TextStyle(color: colors.textSecondary.withValues(alpha: 0.6)),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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
