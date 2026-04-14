import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Top bar for full player screen with minimize button and overflow menu
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback? onOpenQueue;
  final Widget? castButton;

  const PlayerTopBar({
    super.key,
    required this.onMinimize,
    this.onOpenQueue,
    this.castButton,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          // Minimize button
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: onMinimize,
            tooltip: 'Back',
            iconSize: 32,
          ),

          // "Now Playing" text
          Expanded(
            child: Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),

          if (castButton != null) castButton!,
        ],
      ),
    );
  }


}
