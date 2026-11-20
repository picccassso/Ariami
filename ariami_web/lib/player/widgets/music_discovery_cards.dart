import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';
import 'package:flutter/material.dart';

import '../theme/player_theme.dart';
import 'hover_builder.dart';
import 'hover_surface.dart';

class RecommendationSection extends StatelessWidget {
  const RecommendationSection({
    super.key,
    required this.title,
    required this.items,
    required this.matchedArtistFor,
    required this.isWishlisted,
    required this.onToggleWishlist,
    required this.onOpenExternal,
    required this.onOpenArtist,
    required this.onSearch,
    this.onDismiss,
  });

  final String title;
  final List<MusicRecommendation> items;
  final String? Function(MusicRecommendation item) matchedArtistFor;
  final bool Function(MusicRecommendation item) isWishlisted;
  final ValueChanged<MusicRecommendation> onToggleWishlist;
  final ValueChanged<Uri> onOpenExternal;
  final ValueChanged<String> onOpenArtist;
  final ValueChanged<MusicRecommendation> onSearch;
  final ValueChanged<MusicRecommendation>? onDismiss;

  @override
  Widget build(BuildContext context) {
    const padding = 40.0;
    const gap = 12.0;
    const targetWidth = 300.0;

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(padding, 4, padding, 10),
          sliver: SliverToBoxAdapter(
            child: Text(
              title,
              style: PlayerTheme.heading(
                14,
                color: context.colors.textSecondary,
              ).copyWith(letterSpacing: 0.7),
            ),
          ),
        ),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.crossAxisExtent - padding * 2)
                .clamp(240.0, double.infinity);
            final count = (width / targetWidth).floor().clamp(1, 4);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(padding, 0, padding, 24),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: 136,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return RecommendationCard(
                      item: item,
                      matchedArtist: matchedArtistFor(item),
                      isWishlisted: isWishlisted(item),
                      onToggleWishlist: () => onToggleWishlist(item),
                      onOpenExternal: onOpenExternal,
                      onOpenArtist: onOpenArtist,
                      onSearch: () => onSearch(item),
                      onDismiss: onDismiss == null ? null : () => onDismiss!(item),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.item,
    required this.matchedArtist,
    required this.isWishlisted,
    required this.onToggleWishlist,
    required this.onOpenExternal,
    required this.onOpenArtist,
    required this.onSearch,
    this.onDismiss,
  });

  final MusicRecommendation item;
  final String? matchedArtist;
  final bool isWishlisted;
  final VoidCallback onToggleWishlist;
  final ValueChanged<Uri> onOpenExternal;
  final ValueChanged<String> onOpenArtist;
  final VoidCallback onSearch;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final musicBrainz = item.musicBrainzUrl;
    final radius = BorderRadius.circular(PlayerTheme.tileRadius);
    final openInLibrary =
        item.kind == MusicRecommendationKind.artist && matchedArtist != null;

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: openInLibrary
            ? () => onOpenArtist(matchedArtist!)
            : () => onOpenExternal(item.lastFmUrl),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: colors.border),
          ),
          child: HoverSurface(
            active: hover,
            base: colors.surfaceHigh,
            highlight: colors.surfaceHover,
            borderRadius: radius,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RecommendationArtwork(item: item),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PlayerTheme.heading(
                              16,
                              color: colors.textPrimary,
                            ).copyWith(
                              decoration: hover
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: colors.textPrimary,
                            ),
                          ),
                          if (item.displaySubtitle != null)
                            Text(
                              item.displaySubtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            item.discoveryReason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    if (matchedArtist != null)
                      _CardPillButton(
                        icon: Icons.library_music_rounded,
                        label: 'In library',
                        tooltip: 'Open $matchedArtist in Ariami',
                        onTap: () => onOpenArtist(matchedArtist!),
                      ),
                    _CardIconAction(
                      icon: isWishlisted
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      tooltip: isWishlisted
                          ? 'Remove from wishlist'
                          : 'Save to wishlist',
                      onTap: onToggleWishlist,
                    ),
                    _CardIconAction(
                      icon: Icons.search_rounded,
                      tooltip: 'Search in Ariami',
                      onTap: onSearch,
                    ),
                    if (onDismiss != null)
                      _CardIconAction(
                        icon: Icons.close_rounded,
                        tooltip: 'Not interested',
                        onTap: onDismiss!,
                      ),
                    const Spacer(),
                    PopupMenuButton<Uri>(
                      tooltip: 'Find on…',
                      onSelected: onOpenExternal,
                      itemBuilder: (_) => <PopupMenuEntry<Uri>>[
                        PopupMenuItem(
                          value: item.lastFmUrl,
                          child: const Text('Last.fm'),
                        ),
                        if (musicBrainz != null)
                          PopupMenuItem(
                            value: musicBrainz,
                            child: const Text('MusicBrainz'),
                          ),
                        PopupMenuItem(
                          value: item.youtubeMusicUrl,
                          child: const Text('YouTube Music'),
                        ),
                        PopupMenuItem(
                          value: item.bandcampUrl,
                          child: const Text('Bandcamp'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(PlayerTheme.cardRadius),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Find on…',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendationArtwork extends StatelessWidget {
  const _RecommendationArtwork({required this.item});

  final MusicRecommendation item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const size = 56.0;
    final isArtist = item.kind == MusicRecommendationKind.artist;
    final fallback = Container(
      width: size,
      height: size,
      color: colors.band,
      alignment: Alignment.center,
      child: Icon(
        switch (item.kind) {
          MusicRecommendationKind.track => Icons.music_note_rounded,
          MusicRecommendationKind.artist => Icons.person_search_rounded,
          MusicRecommendationKind.album => Icons.album_rounded,
        },
        color: colors.textSecondary,
        size: 24,
      ),
    );

    final imageUrl = item.imageUrl;
    final child = imageUrl == null
        ? fallback
        : Image.network(
            imageUrl.toString(),
            width: size,
            height: size,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context) * 2)
                .round(),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          );

    if (isArtist) return ClipOval(child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(PlayerTheme.coverRadius),
      child: child,
    );
  }
}

class _CardPillButton extends StatelessWidget {
  const _CardPillButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: colors.textPrimary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardIconAction extends StatelessWidget {
  const _CardIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        color: context.colors.textSecondary,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        visualDensity: VisualDensity.compact,
      );
}
