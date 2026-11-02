import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/responsive.dart';

/// The collapsing top of an album, playlist or artist page, used as a
/// [SliverAppBar.flexibleSpace]: the cover, crisp and left-aligned like the
/// front of a sleeve, matching Premium Desktop's detail header. No blurred
/// wash or glow behind it; the page wears the screen's own ground.
class SleeveHeader extends StatelessWidget {
  const SleeveHeader({super.key, required this.cover});

  final Widget cover;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ScreenGround(),
        FlexibleSpaceBar(
          background: Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 8),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isExpandedWidth(context) ? 280 : 200,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.coverRadius),
                    child: cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The screen-wide two-ink ground ([PlayerColors.groundGradient]) cut to a
/// box at the top of the content area, so a pinned bar over scrolling content
/// is opaque without a seam against the ground around it. The content area
/// is the right of the screen; a navigation sidebar takes the rest.
class ScreenGround extends StatelessWidget {
  const ScreenGround({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screen = MediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth <= 0 || box.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final left = screen.width - box.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-left / box.maxWidth * 2 - 1, -1),
              end: Alignment(1, screen.height / box.maxHeight * 2 - 1),
              colors: [colors.base, colors.baseB],
            ),
          ),
        );
      },
    );
  }
}

/// The title block under a [SleeveHeader]: the name in display type, an
/// optional [subtitle] (the album artist, a playlist's description) and a
/// meta line led by what the page is ("Album, 2021, 12 songs, 48 min").
class SleeveTitle extends StatelessWidget {
  const SleeveTitle({
    super.key,
    required this.title,
    this.subtitle,
    required this.meta,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 12),
  });

  final String title;
  final Widget? subtitle;
  final String meta;
  final EdgeInsets padding;

  /// The style for [subtitle], for callers building it.
  static TextStyle subtitleStyle(BuildContext context) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: context.colors.textPrimary,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.display(44, color: colors.textPrimary),
          ),
          const SizedBox(height: 12),
          if (subtitle != null) ...[subtitle!, const SizedBox(height: 2)],
          Text(
            meta,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ],
      ),
    );
  }
}
