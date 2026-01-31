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
    const backgroundColor = Color(0xFF050505);
    const textColor = Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'QUEUE ($queueLength SONG${queueLength != 1 ? 'S' : ''})',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: textColor,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.queue.isNotEmpty && widget.onClear != null)
            IconButton(
              icon: const Icon(Icons.clear_all_rounded, color: textColor),
              onPressed: () => _showClearDialog(context),
              tooltip: 'Clear queue',
            ),
        ],
      ),
      body: Column(
        children: [
          // Queue info header
          if (widget.queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF222222),
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
                        color: Colors.grey[500],
                      ),
                    ),
                    if (widget.queue.currentSong != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.play_circle_fill_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'NOW PLAYING',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
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
                // Rebuild the queue screen to reflect changes
                setState(() {});
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
        backgroundColor: const Color(0xFF111111),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF222222), width: 1),
        ),
        title: const Text(
          'CLEAR QUEUE?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
        content: Text(
          'This will remove all songs from the queue and stop playback.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[400],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey[500],
                letterSpacing: 1.0,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onClear?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'CLEAR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
