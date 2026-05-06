import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../common/mini_player_aware_bottom_sheet.dart';

/// Top bar for full player screen with minimize button.
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;

  const PlayerTopBar({
    super.key,
    required this.onMinimize,
    this.onOpenQueue,
    this.onPlayNext,
    this.onAddToQueue,
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

          if (onPlayNext != null || onAddToQueue != null)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => _showOptionsSheet(context),
              tooltip: 'More options',
            )
          else
            const SizedBox(width: 48, height: 48),
        ],
      ),
    );
  }

  Future<void> _showOptionsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxSheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.9;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: SafeArea(
            minimum: EdgeInsets.only(
              bottom: getMiniPlayerAwareBottomPadding(sheetContext),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Song Options',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (onPlayNext != null)
                    ListTile(
                      leading: const Icon(Icons.skip_next_rounded),
                      title: const Text('Play next'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onPlayNext?.call();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: const Text('Add to queue'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onAddToQueue?.call();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
