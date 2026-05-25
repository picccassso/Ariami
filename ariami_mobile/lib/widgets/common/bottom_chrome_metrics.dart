import 'package:flutter/material.dart';

/// Render height of the mini player widget.
const double kMiniPlayerHeight = 64.0;

/// Maximum visible height of the global download progress bar.
const double kDownloadBarHeight = 4.0;

/// Total height of mini player + download bar overlay.
const double kMiniPlayerOverlayHeight = kMiniPlayerHeight + kDownloadBarHeight;

/// Bottom navigation bar height including device safe-area inset.
///
/// When the IME (keyboard) is open, the bottom nav is obscured and the scaffold
/// body is already laid out above the keyboard — reserve no height for the bar.
double getBottomNavigationBarTotalHeight(BuildContext context) {
  double viewPaddingBottom = 0.0;
  try {
    viewPaddingBottom = MediaQueryData.fromView(View.of(context)).viewPadding.bottom;
  } catch (_) {
    viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
  }
  double viewInsetsBottom = 0.0;
  try {
    viewInsetsBottom = MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
  } catch (_) {
    viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
  }
  return viewInsetsBottom > 0
      ? 0.0
      : kBottomNavigationBarHeight + viewPaddingBottom;
}

/// Total bottom chrome height that content should stay above.
///
/// Includes bottom nav + safe area, and optionally mini player overlay.
double getBottomChromeHeight(
  BuildContext context, {
  required bool isMiniPlayerVisible,
}) {
  final bottomNavHeight = getBottomNavigationBarTotalHeight(context);
  return bottomNavHeight +
      (isMiniPlayerVisible ? kMiniPlayerOverlayHeight : 0.0);
}

/// Bottom margin for floating SnackBars in shells that already account for
/// bottom navigation (e.g., the app's main scaffold messenger host).
///
/// This reserves only the mini-player overlay height plus a small visual gap,
/// preventing double-counting of bottom navigation height.
double getMiniPlayerAwareSnackBarBottomMargin(
  BuildContext context, {
  required bool isMiniPlayerVisible,
  double spacing = 12.0,
}) {
  final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
  final miniPlayerHeight = isMiniPlayerVisible ? kMiniPlayerHeight : 0.0;
  return keyboardVisible ? spacing : miniPlayerHeight + spacing;
}
