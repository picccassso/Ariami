import 'package:flutter/material.dart';
import '../../services/playback_manager.dart';
import 'bottom_chrome_metrics.dart';

/// A widget that wraps bottom sheet content with dynamic padding
/// that accounts for the mini player when it's visible.
///
/// Use this instead of manually adding SafeArea with static padding
/// to bottom sheets. It automatically detects whether music is playing
/// and only adds extra padding when the mini player is visible.
///
/// Example:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (context) => MiniPlayerAwareBottomSheet(
///     child: Column(
///       mainAxisSize: MainAxisSize.min,
///       children: [
///         ListTile(title: Text('Option 1')),
///         ListTile(title: Text('Option 2')),
///       ],
///     ),
///   ),
/// );
/// ```
class MiniPlayerAwareBottomSheet extends StatelessWidget {
  /// The content of the bottom sheet
  final Widget child;

  /// Whether to use SafeArea (default: true)
  final bool useSafeArea;

  const MiniPlayerAwareBottomSheet({
    super.key,
    required this.child,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final playbackManager = PlaybackManager();

    return ListenableBuilder(
      listenable: playbackManager,
      builder: (context, _) {
        final isMiniPlayerVisible = playbackManager.currentSong != null;

        // Calculate bottom padding: mini player + download bar + nav bar (when visible)
        final bottomPadding = isMiniPlayerVisible
            ? getBottomChromeHeight(context, isMiniPlayerVisible: true)
            : 0.0;

        return Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: child,
        );
      },
    );
  }
}

/// Helper function to show a modal bottom sheet with mini player awareness.
///
/// This is a convenience wrapper around [showModalBottomSheet] that
/// automatically wraps the content in [MiniPlayerAwareBottomSheet].
///
/// Example:
/// ```dart
/// showMiniPlayerAwareBottomSheet(
///   context: context,
///   builder: (context) => Column(
///     mainAxisSize: MainAxisSize.min,
///     children: [
///       ListTile(title: Text('Option 1')),
///       ListTile(title: Text('Option 2')),
///     ],
///   ),
/// );
/// ```
Future<T?> showMiniPlayerAwareBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: false, // We handle safe area ourselves
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    builder: (context) => MiniPlayerAwareBottomSheet(
      useSafeArea: useSafeArea,
      child: builder(context),
    ),
  );
}

/// Returns the appropriate bottom padding for content that needs to
/// account for the mini player overlay.
///
/// Use this when you need the padding value directly (e.g., for ListView padding)
/// instead of wrapping content in [MiniPlayerAwareBottomSheet].
///
/// Example:
/// ```dart
/// ListView(
///   padding: EdgeInsets.only(
///     bottom: getMiniPlayerAwareBottomPadding(context),
///   ),
///   children: [...],
/// )
/// ```
double getMiniPlayerAwareBottomPadding(BuildContext context) {
  final playbackManager = PlaybackManager();
  final isMiniPlayerVisible = playbackManager.currentSong != null;
  return getBottomChromeHeight(
    context,
    isMiniPlayerVisible: isMiniPlayerVisible,
  );
}

/// Returns whether the mini player is currently visible.
///
/// Useful for conditional UI adjustments.
bool isMiniPlayerVisible() {
  return PlaybackManager().currentSong != null;
}
