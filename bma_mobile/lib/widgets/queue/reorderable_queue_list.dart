import 'package:flutter/material.dart';
import '../../models/song.dart';

/// Reorderable list widget for the playback queue
class ReorderableQueueList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
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
      itemCount: songs.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isCurrentlyPlaying = index == currentIndex;

        return QueueItem(
          key: ValueKey(song.id),
          song: song,
          index: index,
          isCurrentlyPlaying: isCurrentlyPlaying,
          onTap: onTap != null ? () => onTap!(index) : null,
          onRemove: onRemove != null ? () => onRemove!(index) : null,
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
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const QueueItem({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrentlyPlaying,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(song.id),
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
      child: ListTile(
        leading: _buildLeading(context),
        title: Text(
          song.title,
          style: TextStyle(
            fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal,
            color: isCurrentlyPlaying
                ? Theme.of(context).colorScheme.primary
                : null,
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
                ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
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
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    if (isCurrentlyPlaying) {
      return Icon(
        Icons.play_circle,
        color: Theme.of(context).colorScheme.primary,
        size: 32,
      );
    }

    // Show track number or index
    final displayNumber = song.trackNumber ?? (index + 1);
    return SizedBox(
      width: 32,
      child: Center(
        child: Text(
          displayNumber.toString(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(1, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
