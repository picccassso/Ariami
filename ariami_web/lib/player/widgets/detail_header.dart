import 'package:flutter/material.dart';

import '../theme/player_theme.dart';
import 'artist_link.dart';

/// The top of an album, playlist or artist page: the cover beside the title
/// set in display type, like the front of a sleeve. No wash or glow behind
/// it; the page's colour is the sleeve tone the whole window already wears.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.kindLabel,
    required this.title,
    required this.subtitle,
    required this.metaLine,
    required this.artwork,
    this.linkSubtitle = false,
  });

  /// What the page is ("Album"), leading the meta line.
  final String kindLabel;
  final String title;
  final String subtitle;
  final String metaLine;
  final Widget artwork;

  /// Renders [subtitle] as a link to the artist page — album headers pass the
  /// album artist this way.
  final bool linkSubtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final subtitleStyle = TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              title,
              maxLines: compact ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: PlayerTheme.display(
                compact ? 56 : (constraints.maxWidth >= 900 ? 96 : 76),
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            linkSubtitle
                ? ArtistLink(name: subtitle, maxLines: 2, style: subtitleStyle)
                : Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
            const SizedBox(height: 2),
            Text(
              '$kindLabel, $metaLine',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
                fontFeatures: PlayerTheme.tabular,
              ),
            ),
          ],
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [artwork, const SizedBox(height: 24), details],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              artwork,
              const SizedBox(width: 36),
              Expanded(child: details),
            ],
          ),
        );
      },
    );
  }
}
