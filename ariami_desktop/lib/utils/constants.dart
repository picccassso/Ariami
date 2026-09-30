import 'package:flutter/material.dart';

/// Neutral dark palette shared with Ariami Desktop Premium's setup surfaces:
/// translucent glass over an ambient glow ([AmbientBackdrop]), opaque
/// popovers for dialogs, menus and snack bars.
class AppColors {
  AppColors._();

  static const Color base = Color(0xFF08080A);
  static const Color surfaceHigh = Color(0x10FFFFFF);
  static const Color surfaceHover = Color(0x1CFFFFFF);
  static const Color popover = Color(0xFF1C1C20);
  static const Color border = Color(0x17FFFFFF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x9EFFFFFF);

  /// Ambient backdrop glows, strongest first.
  static const List<Color> glows = [
    Color(0xFF3A3A42),
    Color(0xFF2A2A30),
    Color(0xFF1F1F24),
  ];
}

class AppTheme {
  AppTheme._();

  static const double panelRadius = 20;
  static const double tileRadius = 10;

  static final ThemeData darkTheme = _build();

  static ThemeData _build() {
    const primary = Colors.white;
    const onPrimary = Colors.black;
    const typography = Typography.whiteMountainView;
    final popoverShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tileRadius + 4),
      side: const BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.base,
      canvasColor: AppColors.base,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: onPrimary,
        secondary: primary,
        onSecondary: onPrimary,
        surface: Color(0xFF121214),
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.popover,
        outline: AppColors.border,
        error: Color(0xFFFF5A5F),
        onError: Colors.white,
      ),
      dividerColor: AppColors.border,
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
      hoverColor: AppColors.textPrimary.withValues(alpha: 0.05),
      highlightColor: AppColors.textPrimary.withValues(alpha: 0.04),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      textTheme: typography
          .apply(fontFamily: 'SF Pro Display')
          .copyWith(
            bodyMedium:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            labelLarge: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            // Tight tracking on large type reads as display text rather than
            // scaled-up body copy.
            headlineMedium: _tight(typography.headlineMedium, -0.7),
            headlineSmall: _tight(typography.headlineSmall, -0.5),
            titleLarge: _tight(typography.titleLarge, -0.4)
                ?.copyWith(fontWeight: FontWeight.w700),
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
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: primary,
        dividerColor: AppColors.border,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: const Color(0xF22A2A30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: popoverShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius + 4),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.popover,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: primary,
        elevation: 12,
        shape: popoverShape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: AppColors.surfaceHover,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? onPrimary
                : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primary
                : AppColors.surfaceHover),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.transparent
                : AppColors.border),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStatePropertyAll(
            AppColors.textPrimary.withValues(alpha: 0.18)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: const StadiumBorder(),
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          enabledMouseCursor: SystemMouseCursors.click,
          disabledMouseCursor: SystemMouseCursors.basic,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius - 2),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        // Underline (not outline) keeps a floating label inside the filled
        // pill instead of on its invisible top edge.
        border: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius + 2),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static TextStyle? _tight(TextStyle? style, double letterSpacing) => style
      ?.copyWith(letterSpacing: letterSpacing, fontWeight: FontWeight.w800);
}
