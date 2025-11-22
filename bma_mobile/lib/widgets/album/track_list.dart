import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';

/// Track list item for album detail view
/// Shows track number, title, duration, and overflow menu
class TrackListItem extends StatelessWidget {
  final SongModel track;
  final VoidCallback onTap;
  final bool isCurrentTrack;

  const TrackListItem({
    super.key,
    required this.track,
    required this.onTap,
    this.isCurrentTrack = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        color: isCurrentTrack
            ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
            : null,
        child: Row(
          children: [
            // Track number or playing indicator
            SizedBox(
              width: 32,
              child: _buildTrackNumber(context),
            ),

            const SizedBox(width: 12),

            // Song title
            Expanded(
              child: Text(
                track.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isCurrentTrack ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrentTrack
                      ? Theme.of(context).primaryColor
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 8),

            // Duration
            Text(
              _formatDuration(track.duration),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(width: 8),

            // Overflow menu button
            _buildOverflowMenu(context),
          ],
        ),
      ),
    );
  }

  /// Build track number or playing indicator
  Widget _buildTrackNumber(BuildContext context) {
    if (isCurrentTrack) {
      return Icon(
        Icons.play_arrow,
        color: Theme.of(context).primaryColor,
        size: 20,
      );
    }

    final trackNum = track.trackNumber;
    if (trackNum != null) {
      return Text(
        trackNum.toString(),
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
        ),
        textAlign: TextAlign.center,
      );
    }

    return const SizedBox.shrink();
  }

  /// Build overflow menu button
  Widget _buildOverflowMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 20,
        color: Colors.grey[600],
      ),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem<String>(
          value: 'play_next',
          child: Row(
            children: [
              Icon(Icons.skip_next, size: 20),
              SizedBox(width: 12),
              Text('Play Next'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'add_queue',
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 20),
              SizedBox(width: 12),
              Text('Add to Queue'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'add_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 20),
              SizedBox(width: 12),
              Text('Add to Playlist'),
            ],
          ),
        ),
      ],
    );
  }

  /// Handle menu action selection
  void _handleMenuAction(BuildContext context, String action) {
    String message;
    switch (action) {
      case 'play_next':
        message = 'Added "${track.title}" to play next';
        // TODO: Integrate with playback queue
        break;
      case 'add_queue':
        message = 'Added "${track.title}" to queue';
        // TODO: Integrate with playback queue
        break;
      case 'add_playlist':
        AddToPlaylistScreen.showForSong(context, track.id, albumId: track.albumId);
        return; // Don't show snackbar
      default:
        return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Format duration in seconds to mm:ss
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
