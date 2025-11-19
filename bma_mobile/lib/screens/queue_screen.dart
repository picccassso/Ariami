import 'package:flutter/material.dart';
import '../models/playback_queue.dart';
import '../models/song.dart';
import '../widgets/queue/reorderable_queue_list.dart';

/// Screen displaying the playback queue
class QueueScreen extends StatefulWidget {
  final PlaybackQueue queue;
  final Function(int oldIndex, int newIndex)? onReorder;
  final Function(int index)? onTap;
  final Function(int index)? onRemove;
  final VoidCallback? onClear;

  const QueueScreen({
    super.key,
    required this.queue,
    this.onReorder,
    this.onTap,
    this.onRemove,
    this.onClear,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  @override
  Widget build(BuildContext context) {
    final totalDuration = _calculateTotalDuration(widget.queue.songs);
    final queueLength = widget.queue.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Queue ($queueLength song${queueLength != 1 ? 's' : ''})'),
        actions: [
          if (widget.queue.isNotEmpty && widget.onClear != null)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () => _showClearDialog(context),
              tooltip: 'Clear queue',
            ),
        ],
      ),
      body: Column(
        children: [
          // Queue info header
          if (widget.queue.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total duration: ${_formatDuration(totalDuration)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (widget.queue.currentSong != null)
                    Row(
                      children: [
                        Icon(
                          Icons.play_circle,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Now playing',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

          // Queue list
          Expanded(
            child: ReorderableQueueList(
              songs: widget.queue.songs,
              currentIndex: widget.queue.currentIndex,
              onReorder: (oldIndex, newIndex) {
                // Adjust newIndex for Flutter's reorderable list behavior
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                widget.onReorder?.call(oldIndex, newIndex);
              },
              onTap: widget.onTap,
              onRemove: widget.onRemove,
            ),
          ),
        ],
      ),
    );
  }

  Duration _calculateTotalDuration(List<Song> songs) {
    return songs.fold(
      Duration.zero,
      (total, song) => total + song.duration,
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear queue?'),
        content: const Text(
          'This will remove all songs from the queue and stop playback.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClear?.call();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
