import 'package:flutter/material.dart';

/// Design tokens for the Ariami desktop app, ported from Desktop Premium's
/// neutral dark theme (`PlayerTheme`) and the CLI web dashboard: a flat
/// graphite ground divided by hairline rules, Archivo in three widths, crisp
/// corners and no accent colour — active states invert ink and ground. Colour
/// is reserved for status (running, warning, destructive) so it always
/// carries meaning. Translucent glass over an ambient glow ([AmbientBackdrop])
/// is only for the setup screens; popovers, dialogs and snack bars stay opaque.
class AppColors {
  AppColors._();

  /// The window's ground.
  static const Color base = Color(0xFF1C1D20);

  /// An opaque stand-in for the ground — rings and badges that must mask
  /// what's beneath them while still reading as "the ground colour".
  static const Color surface = Color(0xFF1C1D20);

  /// A raised surface on the ground — cards, settings panels, inputs.
  static const Color surfaceHigh = Color(0xFF27292D);

  /// Raised fill for elements sitting on top of a card (icon chips).
  static const Color surfaceRaised = Color(0xFF2E3034);

  /// Translucent hover / pressed wash.
  static const Color surfaceHover = Color(0x10E8E8E4);

  /// Opaque, elevated fill for dialogs, menus and snack bars.
  static const Color popover = Color(0xFF2A2C30);

  /// Hairline rules between columns and rows, and outlines.
  static const Color border = Color(0xFF34363B);
  static const Color borderStrong = Color(0xFF45474D);

  /// The ink: primary text and icons, and the fill of primary controls.
  static const Color textPrimary = Color(0xFFE8E8E4);

  /// Labels and supporting copy.
  static const Color textSecondary = Color(0xFF8D8F95);

  /// Lowest-emphasis text: placeholders, disabled values.
  static const Color textTertiary = Color(0xFF6B6D73);

  /// Status colours — the only places colour appears at all.
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFF6B6B);

  /// Ambient backdrop glows, strongest first.
  static const List<Color> glows = [
    Color(0xFF3A3A42),
    Color(0xFF2A2A30),
    Color(0xFF1F1F24),
  ];
}

class AppTheme {
  AppTheme._();

  /// Archivo in three widths: regular for reading, condensed for headings
  /// and extra condensed for display titles, the way record sleeves and
  /// spines set long titles without truncating them.
  static const String bodyFamily = 'Archivo';
  static const String headingFamily = 'Archivo Condensed';
  static const String displayFamily = 'Archivo Extra Condensed';

  /// Corner radii by hierarchy: covers crisp like a printed sleeve, cards
  /// and controls slightly softened, floating surfaces (dialogs) a little
  /// more.
  static const double coverRadius = 2;
  static const double cardRadius = 4;
  static const double tileRadius = 6;
  static const double panelRadius = 10;

  /// A section heading: condensed, semi-bold.
  static TextStyle heading(double size, {Color? color}) => TextStyle(
        fontFamily: headingFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.15,
        color: color,
      );

  /// Times and counts: tabular figures so columns of numbers line up.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static final ThemeData darkTheme = _build();

  static ThemeData _build() {
    // No accent: the primary colour is the ink itself, so a selected switch
    // or a filled button reads as ink on ground, inverted.
    const primary = AppColors.textPrimary;
    const onPrimary = AppColors.base;
    final baseTypography = Typography.whiteMountainView;
    final popoverShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: AppColors.border),
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
      brightness: Brightness.dark,
      fontFamily: bodyFamily,
      scaffoldBackgroundColor: AppColors.base,
      canvasColor: AppColors.base,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: onPrimary,
        secondary: primary,
        onSecondary: onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainer: AppColors.surfaceRaised,
        surfaceContainerHighest: AppColors.popover,
        outline: AppColors.border,
        error: AppColors.danger,
        onError: Colors.white,
      ),
      splashFactory: NoSplash.splashFactory,
      dividerColor: AppColors.border,
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
      hoverColor: AppColors.surfaceHover,
      highlightColor: AppColors.surfaceHover,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
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
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            bodyLarge: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
              height: 1.55,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.55,
            ),
            labelLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          )
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
      // A quiet, centred title rather than Material's large left-aligned one.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: headingFamily,
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.border,
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
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        textStyle: const TextStyle(
          fontFamily: bodyFamily,
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: popoverShape,
        textStyle: const TextStyle(
          fontFamily: bodyFamily,
          color: AppColors.textPrimary,
          fontSize: 13.5,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.popover),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(popoverShape),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(panelRadius)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.popover,
        contentTextStyle: const TextStyle(
          fontFamily: bodyFamily,
          color: AppColors.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: primary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: AppColors.border,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 3,
        borderRadius: BorderRadius.circular(2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? onPrimary
                : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primary
                : AppColors.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.transparent
                : AppColors.border),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: primary,
        side: const BorderSide(color: AppColors.border),
        shape: controlShape,
        labelStyle: const TextStyle(
          fontFamily: bodyFamily,
          color: AppColors.textPrimary,
          fontSize: 13,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: primary,
        inactiveTrackColor: AppColors.border,
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
        thumbColor: WidgetStatePropertyAll(
            AppColors.textPrimary.withValues(alpha: 0.18)),
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
            fontFamily: bodyFamily,
            fontWeight: FontWeight.w600,
          ),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: bodyFamily,
            fontWeight: FontWeight.w500,
          ),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: bodyFamily,
            fontWeight: FontWeight.w500,
          ),
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
      cardTheme: CardThemeData(
        color: AppColors.surfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        // Underline (not outline) so a floating label lands inside the filled
        // field; an outline border floats it onto the top edge, which reads
        // as detached once the border itself is invisible.
        border: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        floatingLabelStyle: const TextStyle(color: AppColors.textPrimary),
        helperStyle: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
        errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12.5),
      ),
    );
  }
}
