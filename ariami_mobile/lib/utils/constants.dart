import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AppTheme {
  // Modern Shape
  static const double _defaultRadius = 20.0;

  static ThemeData buildTheme({
    required Brightness brightness,
    required Color seedColor,
  }) {
    final isDark = brightness == Brightness.dark;
    
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // Derived colors for specific components to maintain premium feel
    // Use a stronger blend of the primary color so the theme feels integrated across all screens
    final scaffoldBg = isDark 
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.60), seedColor)
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.60), seedColor);
        
    final surfaceDark = isDark 
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.40), seedColor)
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.40), seedColor);
        
    final surfaceLight = isDark 
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.20), seedColor)
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.20), seedColor);
    
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white70 : Colors.black54;
    final dividerColor = isDark ? Colors.white24 : Colors.black12;

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
        displayLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -1.0, color: textPrimary),
        displayMedium: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5, color: textPrimary),
        displaySmall: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        headlineMedium: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: textPrimary),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textPrimary),
        bodyLarge: TextStyle(fontWeight: FontWeight.w400, fontSize: 16, color: textSecondary),
        bodyMedium: TextStyle(fontWeight: FontWeight.w400, fontSize: 14, color: textSecondary),
      ),

      // Component Themes
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (BuildContext context) => const Icon(LucideIcons.chevronLeft, size: 20),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
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
  static ThemeData get lightTheme => buildTheme(brightness: Brightness.light, seedColor: Colors.white);
  static ThemeData get darkTheme => buildTheme(brightness: Brightness.dark, seedColor: Colors.white);
}
