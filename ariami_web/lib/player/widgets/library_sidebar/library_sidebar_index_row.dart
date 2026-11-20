part of '../library_sidebar.dart';

/// One row of the expanded sidebar, read like an index: a slim gutter that
/// carries the section's letter where the alphabet turns over, the cover, the
/// name, and a quiet count on the right.
///
/// The cover carries the per-entry marks — the quick-jump number, the play
/// button while hovered, playing bars while the entry plays — so the gutter
/// is left to the alphabet alone.
class _IndexRow extends StatelessWidget {
  const _IndexRow({
    required this.title,
    required this.art,
    required this.sourceId,
    required this.onStart,
    required this.onTap,
    this.subtitle,
    this.meta,
    this.letter,
    this.pinned = false,
    this.active = false,
    this.playing = false,
    this.animating = false,
    this.selection = SidebarEntrySelection.none,
    this.quickJumpIndex,
    this.onSecondaryTapDown,
  });

  final String title;

  /// The cover, already sized to [_IndexRow.artSize].
  final Widget art;
  final String? subtitle;
  final String? meta;
  final String? letter;
  final bool pinned;

  /// Playing or open: the title takes the heavier weight.
  final bool active;
  final bool playing;
  final bool animating;
  final SidebarEntrySelection selection;
  final int? quickJumpIndex;
  final String sourceId;
  final VoidCallback onStart;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  static const double artSize = 40;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quickJumpHighlighted = quickJumpIndex != null &&
        context.select<QuickJumpService?, bool>(
          (s) => s?.highlightedIndex == (quickJumpIndex! - 1),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      onTap: onTap,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hover) => HoverSurface(
          active: hover || selection.selected || quickJumpHighlighted,
          base: Colors.transparent,
          highlight: colors.surfaceHover,
          borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
          padding: const EdgeInsets.fromLTRB(0, 5, 10, 5),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: letter == null
                    ? null
                    : Text(
                        letter!,
                        textAlign: TextAlign.center,
                        style: PlayerTheme.display(18,
                            color: colors.textSecondary),
                      ),
              ),
              const SizedBox(width: 4),
              SizedBox.square(
                dimension: artSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: art),
                    if (playing || hover)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: hover
                                ? _SidebarPlayButton(
                                    sourceId: sourceId, onStart: onStart)
                                : PlayingBars(
                                    playing: animating,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                          ),
                        ),
                      ),
                    if (quickJumpIndex != null)
                      _QuickJumpBadge(number: quickJumpIndex!),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: colors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (pinned) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Pinned',
                  child: Icon(Icons.push_pin_outlined,
                      size: 14, color: colors.textSecondary),
                ),
              ],
              if (meta != null) ...[
                const SizedBox(width: 8),
                Text(
                  meta!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    fontFeatures: PlayerTheme.tabular,
                  ),
                ),
              ],
              if (selection.selected) ...[
                const SizedBox(width: 8),
                const _SelectedCheck(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
