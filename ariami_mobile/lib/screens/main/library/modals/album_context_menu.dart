import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../services/api/connection_service.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import 'collection_context_menu.dart';
import '../../../../utils/image_decode.dart';

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
  required VoidCallback onSelectMultiple,
}) {
  final resolvedCoverArt = connectionService.resolveServerUrl(album.coverArt);

  return showCollectionContextMenu(
    context: context,
    noun: 'Album',
    isFullyDownloaded: isFullyDownloaded,
    isPinned: isPinned,
    onPlay: onPlay,
    onAddToQueue: onAddToQueue,
    onDownload: onDownload,
    onTogglePin: onTogglePin,
    onSelectMultiple: onSelectMultiple,
    header: AriamiSheetHeader(
      title: album.title,
      subtitle: album.artist,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: resolvedCoverArt != null && resolvedCoverArt.isNotEmpty
              ? Image(
                  image: resizedForDisplay(
                    context,
                    NetworkImage(
                      resolvedCoverArt,
                      headers: connectionService.authHeaders,
                    ),
                    44,
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[300], child: const Icon(Icons.album)),
                )
              : Container(
                  color: Colors.grey[300], child: const Icon(Icons.album)),
        ),
      ),
    ),
  );
}
