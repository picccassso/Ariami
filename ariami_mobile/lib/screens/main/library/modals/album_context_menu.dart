import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../services/api/connection_service.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

/// Context menu shown when long-pressing an album.
class AlbumContextMenu extends StatelessWidget {
  final AlbumModel album;
  final ConnectionService connectionService;
  final bool isFullyDownloaded;
  final bool isPinned;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;
  final VoidCallback onDownload;
  final VoidCallback onTogglePin;

  const AlbumContextMenu({
    super.key,
    required this.album,
    required this.connectionService,
    required this.isFullyDownloaded,
    this.isPinned = false,
    required this.onPlay,
    required this.onAddToQueue,
    required this.onDownload,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedCoverArt = connectionService.resolveServerUrl(album.coverArt);
    return SafeArea(
      minimum: EdgeInsets.only(
        bottom: getMiniPlayerAwareBottomPadding(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with album info
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey[300],
                    child:
                        resolvedCoverArt != null && resolvedCoverArt.isNotEmpty
                            ? Image.network(
                                resolvedCoverArt,
                                fit: BoxFit.cover,
                                headers: connectionService.authHeaders,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.album),
                              )
                            : const Icon(Icons.album),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        album.artist,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            title: const Text('Play Album'),
            onTap: () {
              Navigator.pop(context);
              onPlay();
            },
          ),
          ListTile(
            leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(isPinned ? 'Unpin' : 'Pin to Top'),
            onTap: () {
              Navigator.pop(context);
              onTogglePin();
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
              title: const Text('Download Album'),
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

/// Shows the album context menu bottom sheet.
Future<void> showAlbumContextMenu({
  required BuildContext context,
  required AlbumModel album,
  required ConnectionService connectionService,
  required bool isFullyDownloaded,
  bool isPinned = false,
  required VoidCallback onPlay,
  required VoidCallback onAddToQueue,
  required VoidCallback onDownload,
  required VoidCallback onTogglePin,
}) {
  return showModalBottomSheet(
    context: context,
    builder: (BuildContext context) {
      return AlbumContextMenu(
        album: album,
        connectionService: connectionService,
        isFullyDownloaded: isFullyDownloaded,
        isPinned: isPinned,
        onPlay: onPlay,
        onAddToQueue: onAddToQueue,
        onDownload: onDownload,
        onTogglePin: onTogglePin,
      );
    },
  );
}
