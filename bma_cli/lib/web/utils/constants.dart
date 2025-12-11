import 'package:flutter/material.dart';

class AppTheme {
  // Pure black with subtle grey accents for refinement
  static const Color _pureBlack = Color(0xFF000000);
  static const Color _darkGrey = Color(0xFF1A1A1A);
  static const Color _borderGrey = Color(0xFF2A2A2A);

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _pureBlack,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      secondary: Colors.white70,
      surface: _darkGrey,
      onPrimary: _pureBlack,
      onSecondary: _pureBlack,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _pureBlack,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _pureBlack,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white54,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: _darkGrey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderGrey, width: 1),
      ),
    ),
    cardColor: _darkGrey,
    dividerColor: _borderGrey,
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _pureBlack,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      secondary: Colors.white70,
      surface: _darkGrey,
      onPrimary: _pureBlack,
      onSecondary: _pureBlack,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _pureBlack,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _pureBlack,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white54,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: _darkGrey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderGrey, width: 1),
      ),
    ),
    cardColor: _darkGrey,
    dividerColor: _borderGrey,
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoTransitionBuilder(),
        TargetPlatform.iOS: _NoTransitionBuilder(),
        TargetPlatform.linux: _NoTransitionBuilder(),
        TargetPlatform.macOS: _NoTransitionBuilder(),
        TargetPlatform.windows: _NoTransitionBuilder(),
      },
    ),
  );
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
