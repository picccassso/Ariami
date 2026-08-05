import 'package:flutter/material.dart';

import '../../services/playback_manager.dart';
import '../common/playing_bars.dart';

typedef PlayingCollectionWidgetBuilder = Widget Function(
  BuildContext context,
  bool isCurrent,
  bool isAnimating,
);

/// Rebuilds a library item when its album/playlist becomes the queue source.
class PlayingCollectionBuilder extends StatelessWidget {
  const PlayingCollectionBuilder({
    super.key,
    required this.sourceId,
    required this.builder,
  });

  final String sourceId;
  final PlayingCollectionWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackManager();
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final isCurrent =
            playback.sourceId == sourceId && playback.currentSong != null;
        return builder(
          context,
          isCurrent,
          isCurrent && (playback.isPlaying || playback.isLoading),
        );
      },
    );
  }
}

/// A title that adopts the accent colour while its collection owns the queue.
class PlayingCollectionTitle extends StatelessWidget {
  const PlayingCollectionTitle({
    super.key,
    required this.sourceId,
    required this.text,
    this.style,
    this.enabled = true,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String sourceId;
  final String text;
  final TextStyle? style;
  final bool enabled;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return PlayingCollectionBuilder(
      sourceId: sourceId,
      builder: (context, isCurrent, _) => Text(
        text,
        style: enabled && isCurrent
            ? (style ?? const TextStyle()).copyWith(
                color: Theme.of(context).colorScheme.primary,
              )
            : style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// Equalizer bars shown only while this collection owns the current queue.
class PlayingCollectionIndicator extends StatelessWidget {
  const PlayingCollectionIndicator({
    super.key,
    required this.sourceId,
    this.enabled = true,
    this.size = 18,
    this.leadingSpacing = 0,
    this.trailingSpacing = 0,
    this.artworkBadge = false,
  });

  final String sourceId;
  final bool enabled;
  final double size;
  final double leadingSpacing;
  final double trailingSpacing;
  final bool artworkBadge;

  @override
  Widget build(BuildContext context) {
    return PlayingCollectionBuilder(
      sourceId: sourceId,
      builder: (context, isCurrent, isAnimating) {
        if (!enabled || !isCurrent) return const SizedBox.shrink();

        Widget bars = PlayingBars(
          playing: isAnimating,
          color: Theme.of(context).colorScheme.primary,
          size: size,
        );
        if (artworkBadge) {
          bars = Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: bars,
          );
        }
        if (leadingSpacing == 0 && trailingSpacing == 0) return bars;
        return Padding(
          padding: EdgeInsets.only(
            left: leadingSpacing,
            right: trailingSpacing,
          ),
          child: bars,
        );
      },
    );
  }
}
