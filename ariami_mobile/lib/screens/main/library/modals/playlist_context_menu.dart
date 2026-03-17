import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

/// Context menu shown when long-pressing a playlist.
class PlaylistContextMenu extends StatelessWidget {
  final PlaylistModel playlist;
  final bool isFullyDownloaded;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;
  final VoidCallback onDownload;

  const PlaylistContextMenu({
    super.key,
    required this.playlist,
    required this.isFullyDownloaded,
    required this.onPlay,
    required this.onAddToQueue,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: EdgeInsets.only(
        bottom: getMiniPlayerAwareBottomPadding(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with playlist info
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.purple[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.queue_music, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Play Playlist'),
            onTap: () {
              Navigator.pop(context);
              onPlay();
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Add to Queue'),
            onTap: () {
              Navigator.pop(context);
              onAddToQueue();
            },
          ),
          if (isFullyDownloaded)
            const ListTile(
              leading: Icon(Icons.check, color: Colors.white),
              title: Text('Downloaded'),
              enabled: false,
            )
          else
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download Playlist'),
              onTap: () {
                Navigator.pop(context);
                onDownload();
              },
            ),
        ],
      ),
    );
  }
}

/// Shows the playlist context menu bottom sheet.
Future<void> showPlaylistContextMenu({
  required BuildContext context,
  required PlaylistModel playlist,
  required bool isFullyDownloaded,
  required VoidCallback onPlay,
  required VoidCallback onAddToQueue,
  required VoidCallback onDownload,
}) {
  return showModalBottomSheet(
    context: context,
    builder: (BuildContext context) {
      return PlaylistContextMenu(
        playlist: playlist,
        isFullyDownloaded: isFullyDownloaded,
        onPlay: onPlay,
        onAddToQueue: onAddToQueue,
        onDownload: onDownload,
      );
    },
  );
}
