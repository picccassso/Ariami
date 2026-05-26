import 'package:flutter/material.dart';
import '../../services/playback_manager.dart';
import '../download/global_download_chrome_visibility.dart';
import 'bottom_chrome_metrics.dart';
import 'queue_action_confirmation.dart';

/// Tracks whether the full player screen is currently covering the mini player.
///
/// When the full player is on top, the mini player and bottom navigation bar
/// are visually hidden behind it, so bottom sheets shown from inside the full
/// player should not reserve space for that chrome.
class MiniPlayerVisibility extends ChangeNotifier {
  MiniPlayerVisibility._internal();

  static final MiniPlayerVisibility instance = MiniPlayerVisibility._internal();

  int _fullPlayerStackDepth = 0;

  bool get isFullPlayerOnTop => _fullPlayerStackDepth > 0;

  static void pushFullPlayer() {
    instance._pushFullPlayer();
  }

  static void popFullPlayer() {
    instance._popFullPlayer();
  }

  void _pushFullPlayer() {
    _fullPlayerStackDepth++;
    notifyListeners();
  }

  void _popFullPlayer() {
    if (_fullPlayerStackDepth > 0) {
      _fullPlayerStackDepth--;
      notifyListeners();
    }
  }
}

Listenable get miniPlayerPaddingListenables => Listenable.merge([
      PlaybackManager(),
      MiniPlayerVisibility.instance,
      GlobalDownloadChromeVisibility.instance,
    ]);

/// Rebuilds when playback or full-player visibility changes and supplies
/// [getMiniPlayerAwareBottomPadding] to [builder].
///
/// Use [MiniPlayerScrollPaddingBuilder] for scrollable lists instead — it
/// keeps padding stable while Now Playing is open so scroll position is
/// preserved when returning from the full player.
class MiniPlayerAwareBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, double bottomPadding) builder;

  const MiniPlayerAwareBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: miniPlayerPaddingListenables,
      builder: (context, _) {
        return builder(context, getMiniPlayerAwareBottomPadding(context));
      },
    );
  }
}

/// Rebuilds when playback changes and supplies stable scroll bottom padding.
///
/// Unlike [MiniPlayerAwareBuilder], this does not shrink padding while the
/// full player is open, preventing scroll extent changes and position jumps
/// when returning from Now Playing.
class MiniPlayerScrollPaddingBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, double bottomPadding) builder;

  const MiniPlayerScrollPaddingBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PlaybackManager(),
        GlobalDownloadChromeVisibility.instance,
      ]),
      builder: (context, _) {
        return builder(context, getMiniPlayerScrollBottomPadding(context));
      },
    );
  }
}

/// Returns the appropriate bottom padding for content that needs to
/// account for the mini player overlay.
///
/// Returns 0 when the full player screen is on top, since the mini player
/// and bottom navigation bar are not visible to the user in that case.
/// For scrollable lists, prefer [getMiniPlayerScrollBottomPadding].
double getMiniPlayerAwareBottomPadding(BuildContext context) {
  if (MiniPlayerVisibility.instance.isFullPlayerOnTop) {
    return 0.0;
  }
  return getMiniPlayerScrollBottomPadding(context);
}

/// Bottom padding for scrollable content above the mini player and nav bar.
///
/// Stays constant while the full player is open so [ScrollView] extent and
/// scroll offset are not disturbed when opening or closing Now Playing.
double getMiniPlayerScrollBottomPadding(BuildContext context) {
  final playbackManager = PlaybackManager();
  final isMiniPlayerVisible = playbackManager.currentSong != null;
  return getBottomChromeHeight(
    context,
    isMiniPlayerVisible: isMiniPlayerVisible,
    isDownloadBarVisible: GlobalDownloadChromeVisibility.instance.isBarVisible,
  );
}

/// Returns whether the mini player is currently visible to the user.
bool isMiniPlayerVisible() {
  if (MiniPlayerVisibility.instance.isFullPlayerOnTop) return false;
  return PlaybackManager().currentSong != null;
}

/// Wraps bottom sheet content with dynamic padding that accounts for the
/// mini player when it's visible.
class MiniPlayerAwareBottomSheet extends StatelessWidget {
  final Widget child;
  final bool useSafeArea;

  const MiniPlayerAwareBottomSheet({
    super.key,
    required this.child,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: miniPlayerPaddingListenables,
      builder: (context, _) {
        final bottomPadding = getMiniPlayerAwareBottomPadding(context);
        return Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: child,
        );
      },
    );
  }
}

/// Backwards-compatible wrapper around [showModalBottomSheet] that adds
/// mini-player-aware padding. Prefer [showAriamiSheet] for new code.
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
  dismissQueueActionConfirmation();
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
    useSafeArea: false,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    builder: (context) => MiniPlayerAwareBottomSheet(
      useSafeArea: useSafeArea,
      child: builder(context),
    ),
  );
}

/// Default radius for the rounded top corners of an Ariami sheet.
const double kAriamiSheetCornerRadius = 24.0;

/// Header widget for [showAriamiSheet] — supports a leading visual,
/// a title, and an optional subtitle. Designed to feel like a polished
/// Material 3 sheet header rather than a plain centered label.
class AriamiSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  const AriamiSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Shows a polished, mini-player-aware modal bottom sheet with rounded top
/// corners, a drag handle, and dynamic content sizing.
///
/// The sheet:
///  - sizes itself to its content (capped at 90% of viewport height)
///  - shows a drag handle by default
///  - reserves space below the mini player when one is visible
///  - reserves no extra space when shown from above the full player
///
/// Pass [header] for a consistent title row, then [items] for the actions.
/// For fully custom layouts, pass [child] instead.
Future<T?> showAriamiSheet<T>({
  required BuildContext context,
  Widget? header,
  List<Widget>? items,
  Widget? child,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  Color? backgroundColor,
}) {
  assert(
    (items != null) ^ (child != null),
    'showAriamiSheet requires exactly one of `items` or `child`.',
  );

  dismissQueueActionConfirmation();

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: true,
    useSafeArea: false,
    backgroundColor: backgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(kAriamiSheetCornerRadius),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.9;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(
            bottom: getMiniPlayerAwareBottomPadding(sheetContext),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null) header,
                if (items != null) ...items,
                if (child != null) child,
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}
