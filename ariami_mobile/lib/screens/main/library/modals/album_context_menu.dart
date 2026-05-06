import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../services/api/connection_service.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

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
  final resolvedCoverArt = connectionService.resolveServerUrl(album.coverArt);

  return showAriamiSheet<void>(
    context: context,
    header: AriamiSheetHeader(
      title: album.title,
      subtitle: album.artist,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: resolvedCoverArt != null && resolvedCoverArt.isNotEmpty
              ? Image.network(
                  resolvedCoverArt,
                  fit: BoxFit.cover,
                  headers: connectionService.authHeaders,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.grey[300], child: const Icon(Icons.album)),
                )
              : Container(color: Colors.grey[300], child: const Icon(Icons.album)),
        ),
      ),
    ),
    items: [
      ListTile(
        leading: const Icon(Icons.play_arrow),
        title: const Text('Play Album'),
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
      if (isFullyDownloaded)
        const ListTile(
          leading: Icon(Icons.check, color: Colors.green),
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
  );
}
