import 'package:flutter/material.dart';

class AppTheme {
  // Premium Dark Theme Palette
  static const Color _deepBackground = Color(0xFF050505); // Almost black
  static const Color _surfaceDark = Color(0xFF141414); // Rich dark grey
  static const Color _surfaceLight = Color(0xFF252525); // Lighter surface
  
  // Ultra-Minimalist Accents (Black & White)
  static const Color _primaryRunning = Color(0xFFFFFFFF); // Pure White
  static const Color _secondaryAccent = Color(0xFFBDBDBD); // Light Grey
  static const Color _errorRed = Color(0xFFFF4B4B);

  // Text Colors
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFFAAAAAA);

  // Modern Shape
  static const double _defaultRadius = 20.0;

  static ThemeData lightTheme = darkTheme; // Force Dark Mode as the default premium look

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _deepBackground,
    primaryColor: _primaryRunning,
    
    // Modern B&W Color Scheme
    colorScheme: const ColorScheme.dark(
      primary: _primaryRunning,
      onPrimary: Colors.black, // High contrast text on primary buttons
      primaryContainer: Color(0xFF252525), // Dark grey for secondary action buttons
      onPrimaryContainer: Colors.white,
      secondary: _secondaryAccent,
      onSecondary: Colors.black,
      surface: _surfaceDark,
      onSurface: _textPrimary,
      surfaceContainerHighest: _surfaceLight,
      error: _errorRed,
      outline: Color(0xFF404040),
    ),

    // Typography 
    // (Using default font but optimized for readability and modern feel)
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -1.0, color: _textPrimary),
      displayMedium: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5, color: _textPrimary),
      displaySmall: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary),
      headlineMedium: TextStyle(fontWeight: FontWeight.w600, color: _textPrimary),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: _textPrimary),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: _textPrimary),
      bodyLarge: TextStyle(fontWeight: FontWeight.w400, fontSize: 16, color: _textSecondary),
      bodyMedium: TextStyle(fontWeight: FontWeight.w400, fontSize: 14, color: _textSecondary),
    ),

    // Component Themes
    appBarTheme: const AppBarTheme(
      backgroundColor: _deepBackground,
      foregroundColor: _textPrimary,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent, // Handled by container
      selectedItemColor: Colors.white,
      unselectedItemColor: Color(0xFF666666),
      elevation: 0,
      showSelectedLabels: false, // Cleaner look
      showUnselectedLabels: false,
      type: BottomNavigationBarType.fixed,
    ),
    
    cardTheme: CardThemeData(
      color: _surfaceDark,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_defaultRadius),
        side: const BorderSide(color: Color(0xFF222222), width: 1),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      minVerticalPadding: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),

    iconTheme: const IconThemeData(
      color: _textPrimary,
      size: 24,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _primaryRunning,
      foregroundColor: Colors.black,
      shape: CircleBorder(),
      elevation: 4,
    ),
    
    dividerTheme: const DividerThemeData(
      color: Color(0xFF222222),
      thickness: 1,
    ),
    
    sliderTheme: SliderThemeData(
      activeTrackColor: _primaryRunning,
      inactiveTrackColor: _surfaceLight,
      thumbColor: Colors.white,
      trackHeight: 4,
      overlayColor: _primaryRunning.withOpacity(0.2),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
    ),
  );
}
