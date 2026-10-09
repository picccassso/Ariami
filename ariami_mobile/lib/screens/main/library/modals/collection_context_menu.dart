import 'package:flutter/material.dart';

import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

/// Shared five-item menu for albums and playlists; [noun] fills the
/// "Play ..." and "Download ..." labels.
Future<void> showCollectionContextMenu({
  required BuildContext context,
  required AriamiSheetHeader header,
  required String noun,
  required bool isFullyDownloaded,
  required bool isPinned,
  required VoidCallback onPlay,
  required VoidCallback onAddToQueue,
  required VoidCallback onDownload,
  required VoidCallback onTogglePin,
  required VoidCallback onSelectMultiple,
}) {
  return showAriamiSheet<void>(
    context: context,
    header: header,
    items: [
      ListTile(
        leading: const Icon(Icons.play_arrow),
        title: Text('Play $noun'),
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
        title: const Text('Add to End of Queue'),
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
          title: Text('Download $noun'),
          onTap: () {
            Navigator.pop(context);
            onDownload();
          },
        ),
    ],
  );
}
