import 'package:flutter/material.dart';

import 'queue_action_confirmation.dart';

/// Adds Spotify-style right swipe to queue without dismissing the row.
class SwipeToQueue extends StatefulWidget {
  final Widget child;
  final VoidCallback onAddToQueue;
  final VoidCallback? onRemove;
  final bool addToQueueEnabled;
  final Key itemKey;

  const SwipeToQueue({
    super.key,
    required this.child,
    required this.onAddToQueue,
    required this.itemKey,
    this.onRemove,
    this.addToQueueEnabled = true,
  });

  @override
  State<SwipeToQueue> createState() => _SwipeToQueueState();
}

class _SwipeToQueueState extends State<SwipeToQueue> {
  bool _queueActionLocked = false;

  Future<bool> _handleConfirmDismiss(
    BuildContext context,
    DismissDirection direction,
  ) async {
    if (direction == DismissDirection.startToEnd) {
      if (widget.addToQueueEnabled && !_queueActionLocked) {
        _queueActionLocked = true;
        widget.onAddToQueue();
        showQueueActionConfirmation(context);

        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          _queueActionLocked = false;
        });
      }
      return false;
    }

    if (direction == DismissDirection.endToStart) {
      return widget.onRemove != null;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.addToQueueEnabled && widget.onRemove == null) {
      return widget.child;
    }

    const queueActionColor = Color(0xFF1DB954);

    return Dismissible(
      key: widget.itemKey,
      direction: switch ((widget.addToQueueEnabled, widget.onRemove != null)) {
        (true, true) => DismissDirection.horizontal,
        (true, false) => DismissDirection.startToEnd,
        (false, true) => DismissDirection.endToStart,
        (false, false) => DismissDirection.none,
      },
      dismissThresholds: <DismissDirection, double>{
        DismissDirection.startToEnd: 0.24,
        if (widget.onRemove != null) DismissDirection.endToStart: 0.6,
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: queueActionColor,
        child: const Icon(
          Icons.playlist_add_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
      secondaryBackground: widget.onRemove == null
          ? null
          : Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
      confirmDismiss: (direction) => _handleConfirmDismiss(context, direction),
      onDismissed: (_) => widget.onRemove?.call(),
      child: widget.child,
    );
  }
}
