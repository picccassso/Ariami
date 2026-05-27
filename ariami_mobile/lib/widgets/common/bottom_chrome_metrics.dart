import 'package:flutter/material.dart';

/// Render height of the mini player widget.
const double kMiniPlayerHeight = 64.0;

/// Maximum visible height of the global download progress bar.
const double kDownloadBarHeight = 4.0;

/// Total height of mini player + download bar overlay.
const double kMiniPlayerOverlayHeight = kMiniPlayerHeight + kDownloadBarHeight;

/// Content height of the library batch-download floating bar.
const double kBatchDownloadBarContentHeight = 76.0;

/// Gap between the batch-download bar and bottom chrome (mini player / nav).
const double kBatchDownloadBarBottomGap = 16.0;

/// Extra scroll inset when the library batch-download bar is visible.
const double kBatchDownloadBarScrollInset =
    kBatchDownloadBarContentHeight + kBatchDownloadBarBottomGap;

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
/// The download bar slot is included only while a download session is active.
double getBottomChromeHeight(
  BuildContext context, {
  required bool isMiniPlayerVisible,
  required bool isDownloadBarVisible,
}) {
  final bottomNavHeight = getBottomNavigationBarTotalHeight(context);
  if (!isMiniPlayerVisible) {
    return bottomNavHeight;
  }
  return bottomNavHeight +
      kMiniPlayerHeight +
      (isDownloadBarVisible ? kDownloadBarHeight : 0.0);
}
