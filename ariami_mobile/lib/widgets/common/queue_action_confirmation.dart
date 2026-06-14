import 'dart:async';

import 'package:flutter/material.dart';

import 'mini_player_aware_bottom_sheet.dart';

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
  String message = 'Added to queue',
  String? actionLabel,
  VoidCallback? onAction,
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
    ),
  );
  overlay.insert(_queueConfirmationEntry!);

  _queueConfirmationTimer = Timer(duration, _dismissQueueConfirmation);
}

class _QueueActionConfirmation extends StatefulWidget {
  final double bottomOffset;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _QueueActionConfirmation({
    required this.bottomOffset,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_QueueActionConfirmation> createState() =>
      _QueueActionConfirmationState();
}

class _QueueActionConfirmationState extends State<_QueueActionConfirmation> {
  bool _isVisible = false;

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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAction =
        widget.actionLabel != null && widget.onAction != null;

    final bar = Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
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
                          letterSpacing: 0.5,
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
    // changes around it can never make it bounce.
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
          child: hasAction ? bar : IgnorePointer(child: bar),
        ),
      ),
    );
  }
}
