import 'package:flutter/material.dart';

/// Height of the mini player including its internal vertical margins.
const double kMiniPlayerHeight = 88.0;

/// Maximum visible height of the global download progress bar.
const double kDownloadBarHeight = 4.0;

/// Total height of mini player + download bar overlay.
const double kMiniPlayerOverlayHeight = kMiniPlayerHeight + kDownloadBarHeight;

/// Bottom navigation bar height including device safe-area inset.
double getBottomNavigationBarTotalHeight(BuildContext context) {
  return kBottomNavigationBarHeight + MediaQuery.viewPaddingOf(context).bottom;
}

/// Total bottom chrome height that content should stay above.
///
/// Includes bottom nav + safe area, and optionally mini player overlay.
double getBottomChromeHeight(
  BuildContext context, {
  required bool isMiniPlayerVisible,
}) {
  return getBottomNavigationBarTotalHeight(context) +
      (isMiniPlayerVisible ? kMiniPlayerOverlayHeight : 0.0);
}
