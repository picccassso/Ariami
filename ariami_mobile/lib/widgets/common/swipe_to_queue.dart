import 'package:flutter/material.dart';

import 'queue_action_confirmation.dart';

/// Adds Spotify-style right swipe to queue without dismissing the row.
class SwipeToQueue extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!addToQueueEnabled && onRemove == null) {
      return child;
    }

    const queueActionColor = Color(0xFF1DB954);

    return Dismissible(
      key: itemKey,
      direction: switch ((addToQueueEnabled, onRemove != null)) {
        (true, true) => DismissDirection.horizontal,
        (true, false) => DismissDirection.startToEnd,
        (false, true) => DismissDirection.endToStart,
        (false, false) => DismissDirection.none,
      },
      dismissThresholds: <DismissDirection, double>{
        DismissDirection.startToEnd: 0.24,
        if (onRemove != null) DismissDirection.endToStart: 0.6,
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
      secondaryBackground: onRemove == null
          ? null
          : Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (addToQueueEnabled) {
            onAddToQueue();
            showQueueActionConfirmation(context);
          }
          return false;
        }

        if (direction == DismissDirection.endToStart) {
          return onRemove != null;
        }

        return false;
      },
      onDismissed: (_) => onRemove?.call(),
      child: child,
    );
  }
}
