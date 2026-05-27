import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Top bar for full player screen with minimize button.
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback? onOpenQueue;

  const PlayerTopBar({
    super.key,
    required this.onMinimize,
    this.onOpenQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: onMinimize,
            tooltip: 'Back',
            iconSize: 32,
          ),
          Expanded(
            child: Text(
              'Now Playing',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          const SizedBox(width: 48, height: 48),
        ],
      ),
    );
  }
}
