import 'package:flutter/material.dart';

/// Design tokens and the single theme for the Ariami web dashboard.
///
/// The palette stays black-and-white to match Ariami Desktop; colour is
/// reserved for status (running, warning, destructive) so it always carries
/// meaning. Type is sentence case at a small number of sizes — the dashboard
/// is read at a glance, not shouted at.
class AppTheme {
  // ---------------------------------------------------------------- surfaces
  /// Page canvas.
  static const Color pureBlack = Color(0xFF050505);

  /// Default card / panel fill.
  static const Color surfaceBlack = Color(0xFF121212);

  /// Raised fill for elements sitting on top of a card (icon chips, inputs).
  static const Color surfaceRaised = Color(0xFF1B1B1B);

  /// Fill for a hovered card or row.
  static const Color surfaceHover = Color(0xFF1F1F1F);

  static const Color borderGrey = Color(0xFF262626);
  static const Color borderStrong = Color(0xFF3A3A3A);

  // ------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFFFAFAFA);

  /// Labels and supporting copy. Deliberately lighter than the old
  /// `white54` so 12–13px meta text stays legible on near-black.
  static const Color textSecondary = Color(0xFFA3A3A3);

  /// Lowest-emphasis text: placeholders, disabled values.
  static const Color textTertiary = Color(0xFF6F6F6F);

  // ----------------------------------------------------------------- status
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);

  // ---------------------------------------------------------------- shapes
  static const double radiusSmall = 10;
  static const double radiusMedium = 14;
  static const double radiusLarge = 18;

  static final BorderRadius cardRadius = BorderRadius.circular(radiusLarge);

  /// Card surface used across the dashboard.
  static BoxDecoration cardDecoration({bool hovered = false}) => BoxDecoration(
        color: hovered ? surfaceHover : surfaceBlack,
        borderRadius: cardRadius,
        border: Border.all(color: hovered ? borderStrong : borderGrey),
      );

  /// Retained for the onboarding hero panels.
  static BoxDecoration glassDecoration = BoxDecoration(
    color: Colors.white.withValues(alpha: 0.04),
    borderRadius: BorderRadius.circular(radiusLarge),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
  );

  static LinearGradient backgroundGradient = const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [pureBlack, Color(0xFF0D0D0D)],
  );

  /// Sentence-case section heading, matching Ariami Desktop's dashboard.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.4,
  );

  /// Small supporting label above or beside a value.
  static const TextStyle fieldLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0,
  );

  /// Metadata: timestamps, counts, hints.
  static const TextStyle meta = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    height: 1.45,
  );

  static ThemeData lightTheme = darkTheme; // Enforce dark theme

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: pureBlack,
    primaryColor: Colors.white,
    fontFamily: 'Inter', // Prefer Inter if available
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      secondary: Colors.white,
      surface: surfaceBlack,
      surfaceContainer: surfaceRaised,
      onPrimary: pureBlack,
      onSecondary: pureBlack,
      onSurface: textPrimary,
      outline: borderGrey,
      error: danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: pureBlack,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.3,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -1.6,
        height: 1.1,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      titleLarge: sectionTitle,
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.1,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        color: textPrimary,
        height: 1.55,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textSecondary,
        height: 1.55,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
        side: const BorderSide(color: borderGrey, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    // Every control gets a pointer cursor: this UI is driven by a mouse in a
    // browser tab, and Flutter's default text cursor makes buttons read as
    // inert text. Mirrors the same change in Ariami Desktop.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: pureBlack,
        disabledBackgroundColor: surfaceRaised,
        disabledForegroundColor: textTertiary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        disabledForegroundColor: textTertiary,
        side: const BorderSide(color: borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: textPrimary,
        disabledForegroundColor: textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: textPrimary,
        hoverColor: Colors.white.withValues(alpha: 0.08),
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    switchTheme: SwitchThemeData(
      mouseCursor: WidgetStateMouseCursor.clickable,
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? pureBlack : textSecondary),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : surfaceRaised),
      trackOutlineColor:
          WidgetStateProperty.all(borderStrong),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: textPrimary,
      unselectedLabelColor: textSecondary,
      indicatorColor: Colors.white,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      ),
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: borderGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: borderGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: danger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textTertiary),
      floatingLabelStyle: const TextStyle(color: textPrimary),
      helperStyle: const TextStyle(
        color: textTertiary,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      errorStyle: const TextStyle(color: danger, fontSize: 12.5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceBlack,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
        side: const BorderSide(color: borderGrey),
      ),
      titleTextStyle: sectionTitle,
    ),
    dividerTheme: const DividerThemeData(
      color: borderGrey,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surfaceRaised,
        borderRadius: BorderRadius.circular(radiusSmall),
        border: Border.all(color: borderGrey),
      ),
      textStyle: const TextStyle(color: textPrimary, fontSize: 12.5),
      waitDuration: const Duration(milliseconds: 400),
    ),
    // Snackbars float above a near-black background, so give them a clear
    // outline, shadow and readable text so they're always visible.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surfaceRaised,
      contentTextStyle: const TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: Colors.white,
      elevation: 10,
      width: 460,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: borderStrong),
      ),
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
