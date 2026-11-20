import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'hover_builder.dart';
import 'playing_indicator.dart';

/// A record on a shelf: its cover, its title, and one quiet line beneath.
///
/// No card behind it and no hover zoom: hovering underlines the title and
/// shows a play button on the cover, the way a pointer over a sleeve would.
/// The cover fills the tile's width (or its height, if that is shorter), so
/// the tile works both in fixed grid cells and in rails.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.cover,
    required this.title,
    required this.onOpen,
    required this.onPlay,
    this.subtitle,
    this.onSecondaryTapDown,
    this.playing = false,
    this.animating = false,
    this.unavailable = false,
    this.corner,
  });

  /// Builds the cover at the given square size.
  final Widget Function(double size) cover;
  final String title;
  final Widget? subtitle;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool playing;
  final bool animating;

  /// Offline and not downloaded: shown faded.
  final bool unavailable;

  /// An extra control for the cover's top-right corner, shown on hover
  /// (e.g. removing the tile from a recents row).
  final Widget? corner;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Opacity(
          opacity: unavailable ? 0.4 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size =
                        c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
                    return Align(
                      alignment: Alignment.bottomLeft,
                      child: SizedBox.square(
                        dimension: size,
                        child: Stack(
                          children: [
                            Positioned.fill(child: cover(size)),
                            if (playing)
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: _CoverBadge(
                                  child: PlayingBars(
                                    playing: animating,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: _HoverOnly(
                                visible: hover,
                                child: CoverPlayButton(onPressed: onPlay),
                              ),
                            ),
                            if (corner != null)
                              Positioned(
                                right: 6,
                                top: 6,
                                child:
                                    _HoverOnly(visible: hover, child: corner!),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    PlayerTheme.heading(15, color: colors.textPrimary).copyWith(
                  decoration:
                      hover ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: colors.textPrimary,
                ),
              ),
              if (subtitle != null)
                DefaultTextStyle.merge(
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: subtitle!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The play button that appears on a cover: a small ink square, not a
/// floating disc.
class CoverPlayButton extends StatelessWidget {
  const CoverPlayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'Play',
      child: Material(
        color: colors.textPrimary,
        borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(Icons.play_arrow_rounded, color: colors.base, size: 22),
          ),
        ),
      ),
    );
  }
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
        ),
        child: child,
      );
}

/// Fades a cover control in on hover. Faded-out controls must not swallow
/// clicks meant for the cover (AnimatedOpacity stays hit-testable at 0).
class _HoverOnly extends StatelessWidget {
  const _HoverOnly({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: Motion.fast,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(ignoring: !visible, child: child),
      );
}
