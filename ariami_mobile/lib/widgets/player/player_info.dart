import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/song.dart';
import '../common/adaptive_marquee_text.dart';

/// Song information display with favorite button and intelligent marquee effect
class PlayerInfo extends StatelessWidget {
  final Song song;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const PlayerInfo({
    super.key,
    required this.song,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AdaptiveMarqueeText(
                  key: ValueKey('title-${song.id}-${song.title}'),
                  text: song.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  height: 32,
                ),
                const SizedBox(height: 4),
                AdaptiveMarqueeText(
                  key: ValueKey('artist-${song.id}-${song.artist}'),
                  text: song.artist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  height: 24,
                  velocity: 25.0,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(
              LucideIcons.heart,
              color: isFavorite ? Colors.red : null,
            ),
            onPressed: onToggleFavorite,
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            iconSize: 32,
          ),
        ],
      ),
    );
  }
}
