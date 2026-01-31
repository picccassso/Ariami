import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import '../../models/song.dart';

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
                // Song title with conditional Marquee
                _MarqueeText(
                  text: song.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  height: 32,
                ),
                const SizedBox(height: 4),
                // Artist name with conditional Marquee
                _MarqueeText(
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
          // Favorite button
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
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

/// A helper widget that only scrolls if the text overflows the available width
class _MarqueeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double height;
  final double velocity;

  const _MarqueeText({
    required this.text,
    this.style,
    required this.height,
    this.velocity = 30.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final bool isOverflowing = textPainter.width > constraints.maxWidth;

        if (isOverflowing) {
          return SizedBox(
            height: height,
            child: Marquee(
              text: text,
              style: style,
              scrollAxis: Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              blankSpace: 40.0,
              velocity: velocity,
              pauseAfterRound: const Duration(seconds: 2),
              startPadding: 0.0,
              accelerationDuration: const Duration(seconds: 1),
              accelerationCurve: Curves.linear,
              decelerationDuration: const Duration(milliseconds: 500),
              decelerationCurve: Curves.easeOut,
            ),
          );
        } else {
          return Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.visible,
          );
        }
      },
    );
  }
}
