import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/song.dart';
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
              Icons.queue_music,
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

    return ReorderableListView.builder(
      padding: EdgeInsets.only(
        bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
      ),
      itemCount: widget.songs.length,
      onReorder: widget.onReorder,
      itemBuilder: (context, index) {
        final song = widget.songs[index];
        final isCurrentlyPlaying = index == widget.currentIndex;
        // Default to available if not yet checked (avoids flicker)
        final isAvailable = _availabilityMap[song.id] ?? true;

        return QueueItem(
          key: ValueKey(song.id),
          song: song,
          index: index,
          isCurrentlyPlaying: isCurrentlyPlaying,
          isAvailable: isAvailable,
          onTap: widget.onTap != null ? () => widget.onTap!(index) : null,
          onRemove: widget.onRemove != null ? () => widget.onRemove!(index) : null,
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
    final opacity = isAvailable ? 1.0 : 0.4;

    return Dismissible(
      key: ValueKey(song.id),
      // Always allow swipe-to-remove, even for unavailable songs
      direction: onRemove != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      onDismissed: (_) => onRemove?.call(),
      child: Opacity(
        opacity: opacity,
        child: ListTile(
          leading: _buildLeading(context),
          title: Text(
            song.title,
            style: TextStyle(
              fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal,
              color: isCurrentlyPlaying
                  ? Theme.of(context).colorScheme.primary
                  : (isAvailable ? null : Colors.grey),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrentlyPlaying
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDuration(song.duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
              _buildDragHandle(context),
            ],
          ),
          // Disable tap when unavailable
          onTap: isAvailable ? onTap : null,
        ),
      ),
    );
  }

  /// Build drag handle - disabled when currently playing or unavailable
  Widget _buildDragHandle(BuildContext context) {
    // Currently playing song can't be dragged
    if (isCurrentlyPlaying) {
      return Icon(
        Icons.drag_handle,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      );
    }

    // Unavailable songs can't be dragged
    if (!isAvailable) {
      return Icon(
        Icons.drag_handle,
        color: Theme.of(context).colorScheme.outline,
      );
    }

    // Normal songs can be dragged
    return ReorderableDragStartListener(
      index: index,
      child: Icon(
        Icons.drag_handle,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final connectionService = ConnectionService();

    // Determine artwork URL and cache ID based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (song.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    if (isCurrentlyPlaying) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Album/song artwork using CachedArtwork
              CachedArtwork(
                albumId: cacheId, // Used as cache key
                artworkUrl: artworkUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                fallback: _buildPlaceholder(context),
                fallbackIcon: Icons.music_note,
                fallbackIconSize: 24,
              ),
              // Play icon overlay when currently playing
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.play_circle_filled,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show artwork using CachedArtwork
    return CachedArtwork(
      albumId: cacheId, // Used as cache key
      artworkUrl: artworkUrl,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(4),
      fallback: _buildPlaceholder(context),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
