import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AppTheme {
  // Modern Shape
  static const double _defaultRadius = 20.0;

  static ThemeData buildNeutralTheme({
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;

    final scaffoldBg = isDark ? Colors.black : Colors.white;
    final surfaceDark =
        isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final surfaceLight =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE9E9E9);

    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white70 : Colors.black54;
    final dividerColor = isDark ? Colors.white24 : Colors.black12;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
          )
        : const ColorScheme.light(
            primary: Colors.black,
            onPrimary: Colors.white,
          );

    return _buildBaseTheme(
      brightness: brightness,
      scaffoldBg: scaffoldBg,
      surfaceDark: surfaceDark,
      surfaceLight: surfaceLight,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      dividerColor: dividerColor,
      colorScheme: colorScheme,
    );
  }

  static ThemeData buildColorSourceTheme({
    required Color seedColor,
  }) {
    const brightness = Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // For color-based sources, keep one consistent visual style regardless of light/dark mode.
    final scaffoldBg =
        Color.alphaBlend(Colors.black.withValues(alpha: 0.60), seedColor);
    final surfaceDark =
        Color.alphaBlend(Colors.black.withValues(alpha: 0.40), seedColor);
    final surfaceLight =
        Color.alphaBlend(Colors.black.withValues(alpha: 0.20), seedColor);

    const textPrimary = Colors.white;
    const textSecondary = Colors.white70;
    const dividerColor = Colors.white24;

    return _buildBaseTheme(
      brightness: brightness,
      scaffoldBg: scaffoldBg,
      surfaceDark: surfaceDark,
      surfaceLight: surfaceLight,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      dividerColor: dividerColor,
      colorScheme: colorScheme,
    );
  }

  // Backward-compatible builder used in player-specific theme wrappers.
  static ThemeData buildTheme({
    required Brightness brightness,
    required Color seedColor,
  }) =>
      buildColorSourceTheme(seedColor: seedColor);

  static ThemeData _buildBaseTheme({
    required Brightness brightness,
    required Color scaffoldBg,
    required Color surfaceDark,
    required Color surfaceLight,
    required Color textPrimary,
    required Color textSecondary,
    required Color dividerColor,
    required ColorScheme colorScheme,
  }) {
    final systemOverlayStyle = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: colorScheme.primary,
      colorScheme: colorScheme.copyWith(
        surface: scaffoldBg,
        onSurface: textPrimary,
      ),

      // Typography
      textTheme: TextTheme(
        displayLarge: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: -1.0,
            color: textPrimary),
        displayMedium: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: textPrimary),
        displaySmall:
            TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        headlineMedium:
            TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 20, color: textPrimary),
        titleMedium: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 16, color: textPrimary),
        bodyLarge: TextStyle(
            fontWeight: FontWeight.w400, fontSize: 16, color: textSecondary),
        bodyMedium: TextStyle(
            fontWeight: FontWeight.w400, fontSize: 14, color: textSecondary),
      ),

      // Component Themes
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (BuildContext context) =>
            const Icon(LucideIcons.chevronLeft, size: 20),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemOverlayStyle,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: textPrimary,
        unselectedItemColor: textSecondary,
        elevation: 0,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),

      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_defaultRadius),
          side: BorderSide(color: dividerColor, width: 1),
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
        color: textPrimary,
        size: 24,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const CircleBorder(),
        elevation: 4,
      ),

      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: surfaceLight,
        thumbColor: colorScheme.primary,
        trackHeight: 4,
        overlayColor: colorScheme.primary.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
    );
  }

  // Fallback for places that might still reference the old static themes directly
  // though we should migrate them to use Theme.of(context)
  static ThemeData get lightTheme =>
      buildNeutralTheme(brightness: Brightness.light);
  static ThemeData get darkTheme =>
      buildNeutralTheme(brightness: Brightness.dark);
}
