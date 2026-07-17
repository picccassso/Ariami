import 'package:flutter/material.dart';
import '../../utils/responsive.dart';

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

/// Whether the on-screen keyboard (IME) is currently open.
///
/// Checks both the contextual [MediaQuery] and the raw Flutter view. Nested
/// routes can sometimes consume the contextual inset, while widget tests and
/// focused subtrees may provide a useful contextual inset even when the raw
/// view reports zero.
bool isKeyboardOpen(BuildContext context) {
  double mediaQueryInsetBottom = 0.0;
  double rawViewInsetBottom = 0.0;

  try {
    mediaQueryInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
  } catch (_) {
    // No MediaQuery above this context.
  }

  try {
    rawViewInsetBottom =
        MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
  } catch (_) {
    // No Flutter view above this context.
  }

  return mediaQueryInsetBottom > 0 || rawViewInsetBottom > 0;
}

/// Whether main navigation uses the side rail (wide/tablet layouts) instead
/// of the bottom bar. Falls back to the raw view size so overlay contexts
/// without a contextual [MediaQuery] agree with the main navigation screen.
bool useNavigationRail(BuildContext context) {
  double width;
  try {
    width = MediaQuery.sizeOf(context).width;
  } catch (_) {
    try {
      width = MediaQueryData.fromView(View.of(context)).size.width;
    } catch (_) {
      return false;
    }
  }
  return width >= kTabletBreakpoint;
}

/// Bottom navigation bar height including device safe-area inset.
///
/// When the IME (keyboard) is open, the bottom nav is obscured and the scaffold
/// body is already laid out above the keyboard, so reserve no height for the bar.
/// On rail layouts there is no bottom bar; only the safe-area inset remains.
double getBottomNavigationBarTotalHeight(BuildContext context) {
  double viewPaddingBottom = 0.0;
  try {
    viewPaddingBottom =
        MediaQueryData.fromView(View.of(context)).viewPadding.bottom;
  } catch (_) {
    viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
  }
  if (isKeyboardOpen(context)) {
    return 0.0;
  }
  if (useNavigationRail(context)) {
    return viewPaddingBottom;
  }
  return kBottomNavigationBarHeight + viewPaddingBottom;
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
  // When the keyboard is open the bottom nav and the mini player overlay are
  // both hidden, so scrollable content should run all the way to the keyboard
  // rather than reserving (now-empty) chrome space beneath it.
  if (isKeyboardOpen(context)) {
    return 0.0;
  }
  final bottomNavHeight = getBottomNavigationBarTotalHeight(context);
  // On rail layouts the mini player and download bar are docked in the
  // navigation sidebar rather than overlaid on the content, so content only
  // needs the safe-area inset.
  if (useNavigationRail(context)) {
    return bottomNavHeight;
  }
  if (!isMiniPlayerVisible) {
    return bottomNavHeight;
  }
  return bottomNavHeight +
      kMiniPlayerHeight +
      (isDownloadBarVisible ? kDownloadBarHeight : 0.0);
}
