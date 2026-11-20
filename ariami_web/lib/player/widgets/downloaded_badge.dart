import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/player_host.dart';
import '../theme/player_theme.dart';

/// True when the app is offline and none of the collection's songs are
/// downloaded — i.e. the collection cannot play at all right now. Home cards
/// gray out on this; partially-downloaded collections stay normal (their
/// track lists already dim the individual unavailable songs).
///
/// Provide exactly one of [albumId] or [songIds].
bool collectionUnavailableOffline(
  BuildContext context, {
  String? albumId,
  Iterable<String>? songIds,
}) {
  assert((albumId == null) != (songIds == null));
  final offline = context.select<ConnectionController, bool>(
    (c) => c.isOfflineActive,
  );
  if (!offline) return false;
  final hasAny = maybeSelectProvider<PlayerDownloadsBridge?, bool>(
    context,
    (d) => d == null
        ? false
        : albumId != null
            ? d.hasAlbumDownloads(albumId)
            : d.isAnySongDownloaded(songIds!),
    fallback: false,
  );
  return !hasAny;
}

class DownloadedBadge extends StatelessWidget {
  const DownloadedBadge({super.key, this.size = 14, this.ring = true});

  final double size;

  /// Whether to paint a surface-coloured ring so the badge stands out when
  /// overlapping artwork edges.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.green[600],
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.download_done_rounded,
        size: size * 0.68,
        color: Colors.white,
      ),
    );
    if (!ring) return badge;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: context.colors.surface,
        shape: BoxShape.circle,
      ),
      child: badge,
    );
  }
}

class RecentSearchBadge extends StatelessWidget {
  const RecentSearchBadge({super.key, this.size = 14, this.ring = true});

  final double size;

  /// Whether to paint a surface-coloured ring so the badge stands out when
  /// overlapping artwork edges.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.history_rounded,
        size: size * 0.68,
        color: Colors.white,
      ),
    );
    if (!ring) return badge;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: context.colors.surface,
        shape: BoxShape.circle,
      ),
      child: badge,
    );
  }
}

/// Overlays a [DownloadedBadge] on the bottom-left corner and/or a
/// [RecentSearchBadge] on the top-right corner of [artwork].
class ArtworkWithDownloadedBadge extends StatelessWidget {
  const ArtworkWithDownloadedBadge({
    super.key,
    required this.artwork,
    required this.downloaded,
    this.inRecentSearch = false,
    this.badgeSize = 14,
  });

  final Widget artwork;
  final bool downloaded;
  final bool inRecentSearch;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    if (!downloaded && !inRecentSearch) return artwork;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        artwork,
        if (downloaded)
          Positioned(
            left: -3,
            bottom: -3,
            child: DownloadedBadge(size: badgeSize),
          ),
        if (inRecentSearch)
          Positioned(
            right: -3,
            top: -3,
            child: RecentSearchBadge(size: badgeSize),
          ),
      ],
    );
  }
}
