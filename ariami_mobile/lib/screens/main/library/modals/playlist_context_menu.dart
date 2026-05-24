import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

/// Shows the playlist context menu bottom sheet.
Future<void> showPlaylistContextMenu({
  required BuildContext context,
  required PlaylistModel playlist,
  required bool isFullyDownloaded,
  bool isPinned = false,
  required VoidCallback onPlay,
  required VoidCallback onAddToQueue,
  required VoidCallback onDownload,
  required VoidCallback onTogglePin,
  required VoidCallback onSelectMultiple,
}) {
  return showAriamiSheet<void>(
    context: context,
    header: AriamiSheetHeader(
      title: playlist.name,
      subtitle:
          '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.purple[400],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.queue_music, color: Colors.white),
      ),
    ),
    items: [
      ListTile(
        leading: const Icon(Icons.play_arrow),
        title: const Text('Play Playlist'),
        onTap: () {
          Navigator.pop(context);
          onPlay();
        },
      ),
      ListTile(
        leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
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
      ListTile(
        leading: const Icon(Icons.playlist_add_check),
        title: const Text('Select Multiple'),
        onTap: () {
          Navigator.pop(context);
          onSelectMultiple();
        },
      ),
      if (isFullyDownloaded)
        const ListTile(
          leading: Icon(Icons.check, color: Colors.green),
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
  );
}
