import 'package:flutter/material.dart';
import '../models/playback_queue.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/song.dart';
import '../services/color_extraction_service.dart';
import '../utils/constants.dart';
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
    final colors = ColorExtractionService().currentColors;

    return Theme(
      data: AppTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: colors.primary,
      ),
      child: Builder(
        builder: (themedContext) {
          final theme = Theme.of(themedContext);
          final colorScheme = theme.colorScheme;

          return Scaffold(
            backgroundColor: colorScheme.surface,
            appBar: AppBar(
              title: Text(
                'QUEUE ($queueLength SONG${queueLength != 1 ? 'S' : ''})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: colorScheme.onSurface,
                ),
              ),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: Icon(LucideIcons.chevronLeft, size: 20, color: colorScheme.onSurface),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (widget.queue.isNotEmpty && widget.onClear != null)
                  IconButton(
                    icon: Icon(LucideIcons.trash2, color: colorScheme.onSurface),
                    onPressed: () => _showClearDialog(themedContext),
                    tooltip: 'Clear queue',
                  ),
              ],
            ),
            body: Column(
              children: [
                if (widget.queue.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total duration: ${_formatDuration(totalDuration)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (widget.queue.currentSong != null)
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.playCircle,
                                  size: 16,
                                  color: colorScheme.onSurface,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'NOW PLAYING',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ReorderableQueueList(
                    songs: widget.queue.songs,
                    currentIndex: widget.queue.currentIndex,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      widget.onReorder?.call(oldIndex, newIndex);
                      setState(() {});
                    },
                    onTap: widget.onTap,
                    onRemove: widget.onRemove,
                  ),
                ),
              ],
            ),
          );
        },
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
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        title: Text(
          'CLEAR QUEUE?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: colorScheme.onSurface,
          ),
        ),
        content: Text(
          'This will remove all songs from the queue and stop playback.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onClear?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.onSurface,
                foregroundColor: colorScheme.surface,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(
                'CLEAR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: colorScheme.surface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
