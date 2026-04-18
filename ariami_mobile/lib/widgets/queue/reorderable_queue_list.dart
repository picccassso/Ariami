import 'dart:async';
import 'package:flutter/material.dart';
import '../common/mini_player_aware_bottom_sheet.dart';
import '../../models/song.dart';
import 'queue_display_order.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../services/api/connection_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../common/cached_artwork.dart';

/// Reorderable list widget for the playback queue
class ReorderableQueueList extends StatefulWidget {
  final List<Song> songs;
  final int currentIndex;
  final Function(int oldIndex, int newIndex) onReorder;
  final Function(int index)? onTap;
  final Function(int index)? onRemove;

  const ReorderableQueueList({
    super.key,
    required this.songs,
    required this.currentIndex,
    required this.onReorder,
    this.onTap,
    this.onRemove,
  });

  @override
  State<ReorderableQueueList> createState() => _ReorderableQueueListState();
}

class _ReorderableQueueListState extends State<ReorderableQueueList> {
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();

  /// Map of song ID -> availability (true = available offline or online)
  Map<String, bool> _availabilityMap = {};

  StreamSubscription<OfflineMode>? _offlineStateSubscription;

  @override
  void initState() {
    super.initState();
    _checkSongAvailability();

    // Listen to offline state changes to rebuild availability
    _offlineStateSubscription = _offlineService.offlineModeStream.listen((_) {
      _checkSongAvailability();
    });
  }

  @override
  void didUpdateWidget(ReorderableQueueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check availability when songs list changes
    if (oldWidget.songs != widget.songs) {
      _checkSongAvailability();
    }
  }

  @override
  void dispose() {
    _offlineStateSubscription?.cancel();
    super.dispose();
  }

  /// Check availability for all songs in the queue
  Future<void> _checkSongAvailability() async {
    final newAvailability = <String, bool>{};
    final isOffline = _offlineService.isOffline;

    for (final song in widget.songs) {
      if (isOffline) {
        // When offline, check if song is downloaded or cached
        final isAvailable = await _offlineService.isSongAvailableOffline(song.id);
        newAvailability[song.id] = isAvailable;
      } else {
        // When online, all songs are available
        newAvailability[song.id] = true;
      }
    }

    if (mounted) {
      setState(() {
        _availabilityMap = newAvailability;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.listMusic,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Queue is empty',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    final displayedSongs = QueueDisplayOrder.songsInDisplayOrder(
      widget.songs,
      widget.currentIndex,
    );

    return ReorderableListView.builder(
      padding: EdgeInsets.only(
        bottom: getMiniPlayerAwareBottomPadding(context),
      ),
      itemCount: displayedSongs.length,
      onReorder: widget.onReorder,
      itemBuilder: (context, displayIndex) {
        final song = displayedSongs[displayIndex];
        final isCurrentlyPlaying = displayIndex == 0;
        final realIndex = QueueDisplayOrder.displayIndexToReal(
          displayIndex,
          widget.songs.length,
          widget.currentIndex,
        );
        // Default to available if not yet checked (avoids flicker)
        final isAvailable = _availabilityMap[song.id] ?? true;

        return QueueItem(
          key: ValueKey(song.id),
          song: song,
          index: displayIndex,
          isCurrentlyPlaying: isCurrentlyPlaying,
          isAvailable: isAvailable,
          onTap: widget.onTap != null ? () => widget.onTap!(realIndex) : null,
          onRemove:
              widget.onRemove != null ? () => widget.onRemove!(realIndex) : null,
        );
      },
    );
  }
}

/// Individual queue item widget
class QueueItem extends StatelessWidget {
  final Song song;
  final int index;
  final bool isCurrentlyPlaying;
  final bool isAvailable;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const QueueItem({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrentlyPlaying,
    this.isAvailable = true,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final opacity = isAvailable ? 1.0 : 0.4;

    return Dismissible(
      key: ValueKey(song.id),
      direction: onRemove != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          LucideIcons.trash2,
          color: colorScheme.onSurfaceVariant,
          size: 28,
        ),
      ),
      onDismissed: (_) => onRemove?.call(),
      child: Opacity(
        opacity: opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            decoration: BoxDecoration(
              color: isCurrentlyPlaying ? colorScheme.surfaceContainerHighest : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: isCurrentlyPlaying
                  ? Border.all(color: colorScheme.outlineVariant, width: 1)
                  : null,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: _buildLeading(context),
              title: Text(
                song.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrentlyPlaying ? FontWeight.w800 : FontWeight.w600,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                song.artist.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isCurrentlyPlaying ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(song.duration),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildDragHandle(context),
                ],
              ),
              onTap: isAvailable ? onTap : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build drag handle - disabled when currently playing or unavailable
  Widget _buildDragHandle(BuildContext context) {
    final iconColor = isCurrentlyPlaying ? Colors.white38 : Colors.grey[800];

    if (isCurrentlyPlaying || !isAvailable) {
      return Icon(
        LucideIcons.gripHorizontal,
        color: iconColor,
        size: 20,
      );
    }

    return ReorderableDragStartListener(
      index: index,
      child: Icon(
        LucideIcons.gripHorizontal,
        color: Colors.grey[500],
        size: 20,
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final connectionService = ConnectionService();
    String? artworkUrl;
    String cacheId;

    if (song.albumId != null) {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedArtwork(
            albumId: cacheId,
            artworkUrl: artworkUrl,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(12),
            fallback: _buildPlaceholder(context),
            fallbackIcon: LucideIcons.music,
            fallbackIconSize: 24,
            sizeHint: ArtworkSizeHint.thumbnail,
          ),
          if (isCurrentlyPlaying)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.play,
                      color: Colors.black,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        LucideIcons.music,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(1, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
