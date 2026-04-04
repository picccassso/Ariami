import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// Height of the mini player including its internal vertical margins.
const double kMiniPlayerHeight = 88.0;

/// Maximum visible height of the global download progress bar.
const double kDownloadBarHeight = 4.0;

/// Total height of mini player + download bar overlay.
const double kMiniPlayerOverlayHeight = kMiniPlayerHeight + kDownloadBarHeight;

// #region agent log
void debugLogBottomLayout({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'initial',
}) {
  final payload = <String, Object?>{
    'sessionId': 'c796da',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  unawaited(() async {
    try {
      await File('/Users/alex/Documents/Ariami/Ariami/.cursor/debug-c796da.log')
          .writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }());
}
// #endregion

/// Bottom navigation bar height including device safe-area inset.
///
/// When the IME (keyboard) is open, the bottom nav is obscured and the scaffold
/// body is already laid out above the keyboard — reserve no height for the bar.
double getBottomNavigationBarTotalHeight(BuildContext context) {
  final viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
  final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
  final total = viewInsetsBottom > 0
      ? 0.0
      : kBottomNavigationBarHeight + viewPaddingBottom;
  // #region agent log
  debugLogBottomLayout(
    hypothesisId: 'H2',
    location: 'bottom_chrome_metrics.dart:getBottomNavigationBarTotalHeight',
    message: 'Bottom navigation height computed',
    data: {
      'viewPaddingBottom': viewPaddingBottom,
      'viewInsetsBottom': viewInsetsBottom,
      'keyboardVisible': viewInsetsBottom > 0,
      'total': total,
    },
  );
  // #endregion
  return total;
}

/// Total bottom chrome height that content should stay above.
///
/// Includes bottom nav + safe area, and optionally mini player overlay.
double getBottomChromeHeight(
  BuildContext context, {
  required bool isMiniPlayerVisible,
}) {
  final bottomNavHeight = getBottomNavigationBarTotalHeight(context);
  final total =
      bottomNavHeight + (isMiniPlayerVisible ? kMiniPlayerOverlayHeight : 0.0);
  // #region agent log
  debugLogBottomLayout(
    hypothesisId: 'H3',
    location: 'bottom_chrome_metrics.dart:getBottomChromeHeight',
    message: 'Bottom chrome height computed',
    data: {
      'isMiniPlayerVisible': isMiniPlayerVisible,
      'keyboardVisible': MediaQuery.viewInsetsOf(context).bottom > 0,
      'bottomNavHeight': bottomNavHeight,
      'miniPlayerOverlayHeight':
          isMiniPlayerVisible ? kMiniPlayerOverlayHeight : 0.0,
      'total': total,
    },
  );
  // #endregion
  return total;
}
