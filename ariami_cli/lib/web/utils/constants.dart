import 'package:flutter/material.dart';

/// Design tokens and the single theme for the Ariami web dashboard.
///
/// Mirrors Ariami Desktop Premium's neutral dark theme (`PlayerTheme`): a
/// flat graphite ground divided by hairline rules, Archivo in three widths,
/// crisp corners and no accent colour — active states invert ink and ground.
/// Colour is reserved for status (running, warning, destructive) so it always
/// carries meaning.
class AppTheme {
  /// The page's ground.
  static const Color base = Color(0xFF1C1D20);

  /// Default card / panel fill, a step up from [base].
  static const Color surface = Color(0xFF27292D);

  /// Raised fill for elements sitting on top of a card (icon chips, inputs).
  static const Color surfaceRaised = Color(0xFF2E3034);

  /// Fill for a hovered card or row.
  static const Color surfaceHover = Color(0xFF2C2E32);

  /// Opaque, elevated fill for dialogs, menus and snack bars.
  static const Color popover = Color(0xFF2A2C30);

  static const Color border = Color(0xFF34363B);
  static const Color borderStrong = Color(0xFF45474D);

  /// The ink: primary text and icons, and the fill of primary controls.
  static const Color textPrimary = Color(0xFFE8E8E4);

  /// Labels and supporting copy.
  static const Color textSecondary = Color(0xFF8D8F95);

  /// Lowest-emphasis text: placeholders, disabled values.
  static const Color textTertiary = Color(0xFF6B6D73);

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFF6B6B);

  /// Archivo in three widths: regular for reading, condensed for headings
  /// and extra condensed for display titles.
  static const String bodyFamily = 'Archivo';
  static const String headingFamily = 'Archivo Condensed';
  static const String displayFamily = 'Archivo Extra Condensed';

  /// Corner radii by hierarchy: badges crisp, controls and cards slightly
  /// softened, floating surfaces (dialogs) a little more.
  static const double radiusSmall = 4;
  static const double radiusMedium = 6;
  static const double radiusLarge = 10;

  static final BorderRadius cardRadius = BorderRadius.circular(radiusMedium);

  static BoxDecoration cardDecoration({bool hovered = false}) => BoxDecoration(
        color: hovered ? surfaceHover : surface,
        borderRadius: cardRadius,
        border: Border.all(color: hovered ? borderStrong : border),
      );

  /// Sentence-case section heading, matching Ariami Desktop's dashboard.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: headingFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.15,
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

  static const RoundedRectangleBorder _controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
  );

  static const TextStyle _buttonText = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: bodyFamily,
    scaffoldBackgroundColor: base,
    canvasColor: base,
    primaryColor: textPrimary,
    colorScheme: const ColorScheme.dark(
      primary: textPrimary,
      secondary: textPrimary,
      surface: surface,
      surfaceContainer: surfaceRaised,
      surfaceContainerHighest: popover,
      onPrimary: base,
      onSecondary: base,
      onSurface: textPrimary,
      outline: border,
      error: danger,
    ),
    splashFactory: NoSplash.splashFactory,
    hoverColor: const Color(0x10E8E8E4),
    highlightColor: const Color(0x10E8E8E4),
    appBarTheme: const AppBarTheme(
      backgroundColor: base,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: headingFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 44,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.4,
        height: 0.95,
      ),
      headlineMedium: TextStyle(
        fontFamily: headingFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        height: 1.15,
      ),
      titleLarge: sectionTitle,
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
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
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: border),
      ),
      margin: EdgeInsets.zero,
    ),
    // Every control gets a pointer cursor: this UI is driven by a mouse in a
    // browser tab, and Flutter's default text cursor makes buttons read as
    // inert text. Mirrors the same change in Ariami Desktop.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: textPrimary,
        foregroundColor: base,
        disabledBackgroundColor: surfaceRaised,
        disabledForegroundColor: textTertiary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: _controlShape,
        textStyle: _buttonText,
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        disabledForegroundColor: textTertiary,
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: _controlShape,
        textStyle: _buttonText,
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: textPrimary,
        foregroundColor: base,
        shape: _controlShape,
        textStyle: _buttonText,
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: textPrimary,
        disabledForegroundColor: textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: _controlShape,
        textStyle: _buttonText,
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: textPrimary,
        shape: _controlShape,
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    switchTheme: SwitchThemeData(
      mouseCursor: WidgetStateMouseCursor.clickable,
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? base : textSecondary),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? textPrimary : surfaceRaised),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.transparent
              : border),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: textPrimary,
      linearTrackColor: border,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 3,
      borderRadius: BorderRadius.circular(2),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(3),
      thickness: const WidgetStatePropertyAll(6),
      thumbColor:
          WidgetStatePropertyAll(textPrimary.withValues(alpha: 0.18)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: textPrimary,
      unselectedLabelColor: textSecondary,
      indicatorColor: textPrimary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    // Underline (not outline), as in Desktop Premium, so a floating label
    // lands inside the filled field; the underline marks focus and errors.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceRaised,
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide.none,
      ),
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
      backgroundColor: popover,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
        side: const BorderSide(color: border),
      ),
      titleTextStyle: sectionTitle,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: popover,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
      textStyle: const TextStyle(
        fontFamily: bodyFamily,
        color: textPrimary,
        fontSize: 13.5,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: border,
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
      textStyle: const TextStyle(
        fontFamily: bodyFamily,
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      waitDuration: const Duration(milliseconds: 350),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: popover,
      contentTextStyle: const TextStyle(
        fontFamily: bodyFamily,
        color: textPrimary,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: textPrimary,
      elevation: 8,
      width: 460,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: border),
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
