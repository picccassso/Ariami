import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../common/mini_player_aware_bottom_sheet.dart';

class PlayerSecondaryControls extends StatelessWidget {
  final Widget? outputButton;

  /// Shown under the row, e.g. which device playback is routed to.
  final Widget? outputCaption;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final bool isLyricsVisible;
  final bool hasLyrics;
  final VoidCallback? onToggleLyrics;

  const PlayerSecondaryControls({
    super.key,
    this.outputButton,
    this.outputCaption,
    this.onOpenQueue,
    this.onAddToPlaylist,
    this.onPlayNext,
    this.onAddToQueue,
    this.isLyricsVisible = false,
    this.hasLyrics = false,
    this.onToggleLyrics,
  });

  bool get _hasSongActions =>
      onAddToPlaylist != null || onPlayNext != null || onAddToQueue != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  Icons.lyrics_outlined,
                  color: !hasLyrics
                      ? Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.25)
                      : (isLyricsVisible
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7)),
                ),
                onPressed: hasLyrics ? onToggleLyrics : null,
                tooltip: hasLyrics
                    ? (isLyricsVisible ? 'Hide lyrics' : 'Show lyrics')
                    : 'No lyrics available',
                iconSize: 24,
              ),
              outputButton ?? const SizedBox(width: 48, height: 48),
              if (_hasSongActions)
                IconButton(
                  icon: const Icon(LucideIcons.listPlus),
                  onPressed: () => _showOptionsSheet(context),
                  tooltip: 'Song options',
                  iconSize: 24,
                ),
              IconButton(
                icon: const Icon(LucideIcons.listMusic),
                onPressed: onOpenQueue,
                tooltip: 'View queue',
                iconSize: 24,
              ),
            ],
          ),
          if (outputCaption != null) outputCaption!,
        ],
      ),
    );
  }

  Future<void> _showOptionsSheet(BuildContext context) {
    return showAriamiSheet<void>(
      context: context,
      header: const AriamiSheetHeader(title: 'Song Options'),
      items: [
        if (onAddToPlaylist != null)
          ListTile(
            leading: const Icon(LucideIcons.listPlus),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.pop(context);
              onAddToPlaylist?.call();
            },
          ),
        if (onPlayNext != null)
          ListTile(
            leading: const Icon(Icons.skip_next_rounded),
            title: const Text('Play next'),
            onTap: () {
              Navigator.pop(context);
              onPlayNext?.call();
            },
          ),
        if (onAddToQueue != null)
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Add to end of queue'),
            onTap: () {
              Navigator.pop(context);
              onAddToQueue?.call();
            },
          ),
      ],
    );
  }
}
