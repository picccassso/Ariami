import 'package:ariami_core/ariami_core.dart'
    show
        MusicDiscoveryMix,
        MusicDiscoveryPreferences,
        MusicRecommendation,
        MusicRecommendationKind,
        musicDiscoveryTagLabel;
import 'package:flutter/material.dart';

import '../../utils/image_decode.dart';

class DiscoveryOptInView extends StatelessWidget {
  const DiscoveryOptInView({
    super.key,
    required this.hasApiKey,
    required this.error,
    required this.onEnableImmediately,
    required this.onOpenSetup,
  });

  final bool hasApiKey;
  final String? error;
  final VoidCallback onEnableImmediately;
  final VoidCallback onOpenSetup;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.explore_rounded,
                size: 58,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 18),
              const Text(
                'Discover music from your Ariami listening',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Ariami calculates favourites privately and sends only a few '
                'selected names or exploration tags. There is no scrobbling '
                'and no Last.fm account connection.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (error != null) ...[
                const SizedBox(height: 18),
                DiscoveryErrorCard(message: error!),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: hasApiKey ? onEnableImmediately : onOpenSetup,
                    icon: const Icon(Icons.explore_rounded),
                    label: Text(
                      hasApiKey
                          ? 'Enable music discovery'
                          : 'Add API key and enable',
                    ),
                  ),
                  if (hasApiKey)
                    OutlinedButton(
                      onPressed: onOpenSetup,
                      child: const Text('Customize'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}

class DiscoveryHeader extends StatelessWidget {
  const DiscoveryHeader({
    super.key,
    required this.snapshotSeedCount,
    required this.snapshotGeneratedAt,
    required this.preferences,
    required this.dismissedCount,
    required this.savedCount,
    required this.showSavedOnly,
    required this.onToggleSavedOnly,
    required this.onMixSelected,
    required this.onClearInstrumental,
    required this.onRemoveTag,
    required this.onOpenSetup,
    required this.onRestoreDismissed,
  });

  final int snapshotSeedCount;
  final DateTime? snapshotGeneratedAt;
  final MusicDiscoveryPreferences preferences;
  final int dismissedCount;
  final int savedCount;
  final bool showSavedOnly;
  final ValueChanged<bool> onToggleSavedOnly;
  final ValueChanged<MusicDiscoveryMix> onMixSelected;
  final VoidCallback onClearInstrumental;
  final ValueChanged<String> onRemoveTag;
  final VoidCallback onOpenSetup;
  final VoidCallback onRestoreDismissed;

  @override
  Widget build(BuildContext context) {
    final seedCount = snapshotSeedCount;
    final tags = preferences.preferredTags.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recommended from your listening',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            snapshotGeneratedAt == null
                ? 'New music based on what you actually play in Ariami.'
                : seedCount == 0
                    ? 'Updated ${_relativeTime(snapshotGeneratedAt!)}. Music you already own has been removed.'
                    : 'Using $seedCount private taste seeds · updated ${_relativeTime(snapshotGeneratedAt!)}. Music you already own has been removed.',
          ),
          const SizedBox(height: 4),
          Text(
            discoveryPreferenceSummary(preferences),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final mix in MusicDiscoveryMix.values)
                ChoiceChip(
                  label: Text(_mixChipLabel(mix)),
                  selected: !showSavedOnly && preferences.mix == mix,
                  onSelected: (selected) {
                    if (!selected) return;
                    if (showSavedOnly) onToggleSavedOnly(false);
                    if (preferences.mix != mix) {
                      onMixSelected(mix);
                    }
                  },
                ),
              if (savedCount > 0 || showSavedOnly)
                FilterChip(
                  avatar: const Icon(Icons.bookmark_rounded, size: 16),
                  label: Text('Saved ($savedCount)'),
                  selected: showSavedOnly,
                  onSelected: onToggleSavedOnly,
                ),
              if (preferences.instrumentalOnly)
                InputChip(
                  label: const Text('Instrumental'),
                  onDeleted: onClearInstrumental,
                ),
              for (final tag in tags)
                InputChip(
                  label: Text(musicDiscoveryTagLabel(tag)),
                  onDeleted: () => onRemoveTag(tag),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Tag'),
                tooltip: 'Add or edit exploration tags',
                onPressed: onOpenSetup,
              ),
              if (dismissedCount > 0)
                TextButton(
                  onPressed: onRestoreDismissed,
                  child: Text('Restore $dismissedCount hidden'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime value) {
    final difference = DateTime.now().toUtc().difference(value.toUtc());
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class DiscoveryNoticeBanner extends StatelessWidget {
  const DiscoveryNoticeBanner({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscoveryErrorCard extends StatelessWidget {
  const DiscoveryErrorCard({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onAction,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                    side: BorderSide(
                      color: scheme.onErrorContainer.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DiscoveryOfflineView extends StatelessWidget {
  const DiscoveryOfflineView({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 46),
            const SizedBox(height: 12),
            const Text(
              'Connect to discover new music',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'No cached recommendations are saved for this filter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class DiscoveryColdStartView extends StatelessWidget {
  const DiscoveryColdStartView({
    super.key,
    required this.isAllTime,
    required this.rangeTitle,
    required this.quickTags,
    required this.onSelectTag,
    required this.onUseAllTime,
    required this.onBrowseLibrary,
  });

  final bool isAllTime;
  final String rangeTitle;
  final List<String> quickTags;
  final ValueChanged<String> onSelectTag;
  final VoidCallback onUseAllTime;
  final VoidCallback onBrowseLibrary;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Column(
          children: [
            const Icon(Icons.explore_outlined, size: 46),
            const SizedBox(height: 12),
            Text(
              isAllTime
                  ? 'Pick a genre to start exploring'
                  : 'No listening recorded in $rangeTitle',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              isAllTime
                  ? 'Ariami does not have listening favourites yet. Choose a '
                      'tag below to discover music right away, or listen in '
                      'your library first.'
                  : 'Try exploring a tag below, or switch back to all-time listening.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (quickTags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final tag in quickTags)
                    ActionChip(
                      label: Text(musicDiscoveryTagLabel(tag)),
                      onPressed: () => onSelectTag(tag),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (!isAllTime)
                  FilledButton(
                    onPressed: onUseAllTime,
                    child: const Text('Use all-time listening'),
                  ),
                OutlinedButton(
                  onPressed: onBrowseLibrary,
                  child: const Text('Browse library'),
                ),
              ],
            ),
          ],
        ),
      );
}

class DiscoveryEmptyView extends StatelessWidget {
  const DiscoveryEmptyView({
    super.key,
    required this.onRefresh,
    required this.onAdjustFilters,
    this.onRestoreDismissed,
  });

  final VoidCallback onRefresh;
  final VoidCallback onAdjustFilters;
  final VoidCallback? onRestoreDismissed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(
          children: [
            const Icon(Icons.travel_explore_rounded, size: 46),
            const SizedBox(height: 12),
            Text(
              onRestoreDismissed != null
                  ? 'All recommendations hidden'
                  : 'No unowned matches yet',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              onRestoreDismissed != null
                  ? 'Restore hidden recommendations or refresh for new ones.'
                  : 'Try changing your refinements or refresh later.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (onRestoreDismissed != null)
                  FilledButton(
                    onPressed: onRestoreDismissed,
                    child: const Text('Restore hidden'),
                  ),
                OutlinedButton(
                  onPressed: onAdjustFilters,
                  child: const Text('Adjust filters'),
                ),
                OutlinedButton(
                  onPressed: onRefresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ],
        ),
      );
}

class DiscoveryRecommendationGroup extends StatelessWidget {
  const DiscoveryRecommendationGroup({
    super.key,
    required this.title,
    required this.items,
    required this.matchedArtistFor,
    required this.isWishlisted,
    required this.onToggleWishlist,
    required this.onOpenArtist,
    this.onDismiss,
    required this.onFind,
  });

  final String title;
  final List<MusicRecommendation> items;
  final String? Function(MusicRecommendation item) matchedArtistFor;
  final bool Function(MusicRecommendation item) isWishlisted;
  final ValueChanged<MusicRecommendation> onToggleWishlist;
  final ValueChanged<String> onOpenArtist;
  final ValueChanged<MusicRecommendation>? onDismiss;
  final ValueChanged<MusicRecommendation> onFind;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final item in items) _buildCard(context, item),
          ],
        ),
      );

  Widget _buildCard(BuildContext context, MusicRecommendation item) {
    final matchedArtist = matchedArtistFor(item);
    final openInLibrary =
        item.kind == MusicRecommendationKind.artist && matchedArtist != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: openInLibrary
                ? () => onOpenArtist(matchedArtist)
                : () => onFind(item),
            leading: CircleAvatar(
              child: item.imageUrl == null
                  ? _recommendationIcon(item.kind)
                  : ClipOval(
                      child: Image(
                        image: resizedForDisplay(
                          context,
                          NetworkImage(item.imageUrl.toString()),
                          40,
                        ),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _recommendationIcon(item.kind),
                      ),
                    ),
            ),
            title: Text(
              item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              <String>[
                if (item.displaySubtitle != null) item.displaySubtitle!,
                item.discoveryReason,
              ].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: isWishlisted(item)
                      ? 'Remove from wishlist'
                      : 'Save to wishlist',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onToggleWishlist(item),
                  icon: Icon(
                    isWishlisted(item)
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 20,
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Not interested',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onDismiss!(item),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                IconButton(
                  tooltip: 'Find on…',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onFind(item),
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                ),
              ],
            ),
          ),
          if (matchedArtist != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 10),
              child: ActionChip(
                avatar: const Icon(Icons.library_music_rounded, size: 15),
                label: const Text('In library'),
                tooltip: 'Open $matchedArtist in Ariami',
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => onOpenArtist(matchedArtist),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _recommendationIcon(MusicRecommendationKind kind) => Icon(
        switch (kind) {
          MusicRecommendationKind.track => Icons.music_note_rounded,
          MusicRecommendationKind.artist => Icons.person_search_rounded,
          MusicRecommendationKind.album => Icons.album_rounded,
        },
      );
}

String _mixChipLabel(MusicDiscoveryMix mix) => switch (mix) {
      MusicDiscoveryMix.balanced => 'Balanced',
      MusicDiscoveryMix.tracks => 'Tracks',
      MusicDiscoveryMix.artists => 'Artists',
      MusicDiscoveryMix.albums => 'Albums',
    };

String discoveryPreferenceSummary(MusicDiscoveryPreferences preferences) {
  final mix = _mixChipLabel(preferences.mix);
  final tags = preferences.preferredTags.toList()..sort();
  final refinement = <String>[
    if (preferences.instrumentalOnly) 'Instrumental',
    if (tags.isNotEmpty)
      tags.length <= 2
          ? tags.map(musicDiscoveryTagLabel).join(', ')
          : '${tags.take(2).map(musicDiscoveryTagLabel).join(', ')} '
              '+${tags.length - 2}',
  ];
  return '$mix${refinement.isEmpty ? '' : ' · ${refinement.join(' · ')}'} · '
      '${preferences.resultLimit} max · '
      '${MusicDiscoveryPreferences.tasteRangeLabel(preferences.tasteRange)} · '
      'depth ${preferences.seedDepth}';
}
