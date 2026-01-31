import 'package:flutter/material.dart';

class AppTheme {
  // Ultra-Minimalist Black & White Palette
  static const Color _pureBlack = Color(0xFF050505);
  static const Color _darkGrey = Color(0xFF141414);
  static const Color _borderGrey = Color(0xFF2A2A2A);
  static const Color _surfaceGrey = Color(0xFF1A1A1A);

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _pureBlack,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      secondary: Colors.white70,
      surface: _surfaceGrey,
      surfaceContainer: _darkGrey,
      onPrimary: _pureBlack,
      onSecondary: _pureBlack,
      onSurface: Colors.white,
      outline: _borderGrey,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _pureBlack,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _pureBlack,
      selectedItemColor: Colors.white,
      // ignore: deprecated_member_use
      unselectedItemColor: Colors.white54,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardThemeData(
      color: _darkGrey,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _borderGrey, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _pureBlack,
        elevation: 0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
    ),
    iconTheme: const IconThemeData(
      color: Colors.white,
    ),
    dividerTheme: const DividerThemeData(
      color: _borderGrey,
      thickness: 1,
    ),
    cardColor: _darkGrey,
    dividerColor: _borderGrey,
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );

  static ThemeData darkTheme = lightTheme;
}
