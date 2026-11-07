import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/playback_manager.dart';
import 'mini_player_aware_bottom_sheet.dart';
import '../../utils/constants.dart';

OverlayEntry? _queueConfirmationEntry;
Timer? _queueConfirmationTimer;
DateTime? _lastQueueConfirmationTime;
String? _lastQueueConfirmationMessage;

void _dismissQueueConfirmation() {
  _queueConfirmationTimer?.cancel();
  _queueConfirmationTimer = null;
  _queueConfirmationEntry?.remove();
  _queueConfirmationEntry = null;
}

void dismissQueueActionConfirmation() {
  _dismissQueueConfirmation();
}

void showQueueActionConfirmation(
  BuildContext context, {
  String message = 'Added to end of queue',
  String? actionLabel,
  VoidCallback? onAction,
  String? secondaryActionLabel,
  VoidCallback? onSecondaryAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final now = DateTime.now();
  if (_lastQueueConfirmationTime != null &&
      _lastQueueConfirmationMessage == message &&
      now.difference(_lastQueueConfirmationTime!) < const Duration(milliseconds: 500)) {
    return;
  }
  _lastQueueConfirmationTime = now;
  _lastQueueConfirmationMessage = message;

  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  _dismissQueueConfirmation();

  // Snapshot the resting position ONCE, from the caller's context, and freeze
  // it for the toast's lifetime. The toast must not chase live UI changes
  // (mini player appearing, download bar toggling, playback ticks, list
  // reflows): reacting to those is exactly what made it "bounce". A fixed
  // offset means the only motion is the intentional slide-in entrance.
  final bottomOffset = getMiniPlayerAwareBottomPadding(context) + 24;

  // Note: the widget below is intentionally created without a per-build key.
  // An OverlayEntry's builder re-runs whenever the root Overlay rebuilds (e.g.
  // on any MediaQuery change such as the keyboard animating). Minting a new
  // UniqueKey() inside the builder would tear down and recreate the state on
  // every such rebuild, replaying the entrance animation and causing the
  // toast to "bounce" repeatedly. Reusing a single instance keeps its state.
  _queueConfirmationEntry = OverlayEntry(
    builder: (context) => _QueueActionConfirmation(
      bottomOffset: bottomOffset,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              _dismissQueueConfirmation();
              onAction();
            },
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction == null
          ? null
          : () {
              _dismissQueueConfirmation();
              onSecondaryAction();
            },
    ),
  );
  overlay.insert(_queueConfirmationEntry!);

  _queueConfirmationTimer = Timer(duration, _dismissQueueConfirmation);
}

/// Offers to undo an action the user just took; every undo in the app shares
/// this label and window so they behave the same everywhere.
void showUndoToast(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  showQueueActionConfirmation(
    context,
    message: message,
    actionLabel: 'Undo',
    onAction: onUndo,
    duration: const Duration(seconds: 5),
  );
}

/// Standard toast for songs just added to the playback queue. Shows an Undo
/// action that removes the added range again; [firstIndex] and [count] are
/// the insertion point and number of songs, as returned by
/// [PlaybackManager.addToQueue], [PlaybackManager.playNext] or
/// [PlaybackManager.addAllToQueue].
void showQueueAdditionToast(
  BuildContext context, {
  required String message,
  required int firstIndex,
  int count = 1,
  String? secondaryActionLabel,
  VoidCallback? onSecondaryAction,
}) {
  if (firstIndex < 0 || count <= 0) {
    showQueueActionConfirmation(context, message: message);
    return;
  }
  showQueueActionConfirmation(
    context,
    message: message,
    actionLabel: 'Undo',
    onAction: () => unawaited(_undoQueueAddition(firstIndex, count)),
    duration: const Duration(seconds: 5),
    secondaryActionLabel: secondaryActionLabel,
    onSecondaryAction: onSecondaryAction,
  );
}

Future<void> _undoQueueAddition(int firstIndex, int count) async {
  final manager = PlaybackManager();
  // Remove tail-first so the indices of the remaining additions stay valid.
  for (var i = count - 1; i >= 0; i--) {
    await manager.removeQueueItem(firstIndex + i);
  }
}

class _QueueActionConfirmation extends StatefulWidget {
  final double bottomOffset;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  const _QueueActionConfirmation({
    required this.bottomOffset,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  State<_QueueActionConfirmation> createState() =>
      _QueueActionConfirmationState();
}

class _QueueActionConfirmationState extends State<_QueueActionConfirmation>
    with SingleTickerProviderStateMixin {
  bool _isVisible = false;

  // Swipe-to-dismiss tracking. The drag follows the finger 1:1; past the
  // threshold (or on a fling) the toast animates the rest of the way out and
  // removes itself from the overlay.
  double _dragDx = 0;
  double _width = 0;
  int _dragSign = 1;
  late final AnimationController _leaveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _dismissQueueConfirmation();
      }
    });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isVisible = true;
      });
    });
  }

  @override
  void dispose() {
    _leaveController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_leaveController.isAnimating) return;
    setState(() {
      _dragDx += details.delta.dx;
      _dragSign = _dragDx < 0 ? -1 : 1;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_leaveController.isAnimating) return;
    final pastThreshold = _width > 0 && _dragDx.abs() > _width * 0.25;
    final flung = details.velocity.pixelsPerSecond.dx.abs() > 600;
    if (pastThreshold || flung) {
      _leaveController.forward();
    } else {
      setState(() {
        _dragDx = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAction =
        widget.actionLabel != null && widget.onAction != null;
    final hasSecondaryAction = widget.secondaryActionLabel != null &&
        widget.onSecondaryAction != null;

    final bar = Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(AppTheme.panelRadius),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.panelRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            if (hasAction)
              InkWell(
                onTap: widget.onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    widget.actionLabel!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            if (hasSecondaryAction)
              InkWell(
                onTap: widget.onSecondaryAction,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 16,
                    top: 12,
                    bottom: 12,
                  ),
                  child: Text(
                    widget.secondaryActionLabel!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Fixed position for the toast's lifetime (snapshotted at show-time). Only
    // the entrance slide/fade animates; the anchor never moves, so live UI
    // changes around it can never make it bounce. Dragging sideways past the
    // threshold (or flinging) slides the toast the rest of the way out and
    // removes it, cancelling its auto-dismiss timer.
    return Positioned(
      left: 20,
      right: 20,
      bottom: widget.bottomOffset,
      child: AnimatedSlide(
        offset: _isVisible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _isVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _width = constraints.maxWidth;
              return GestureDetector(
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: AnimatedBuilder(
                  animation: _leaveController,
                  builder: (context, child) {
                    final leave = _leaveController.value;
                    final dx =
                        (_dragDx + _dragSign * leave * _width) / _width;
                    return FractionalTranslation(
                      translation: Offset(dx, 0),
                      child: Opacity(
                        opacity: 1 - leave,
                        child: child,
                      ),
                    );
                  },
                  child: (hasAction || hasSecondaryAction)
                      ? bar
                      : IgnorePointer(child: bar),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
