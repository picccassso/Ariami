import 'package:flutter/material.dart';

import '../../../../models/api_models.dart';
import '../../../../screens/playlist/widgets/playlist_cover_art.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import 'collection_context_menu.dart';

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
  return showCollectionContextMenu(
    context: context,
    noun: 'Playlist',
    isFullyDownloaded: isFullyDownloaded,
    isPinned: isPinned,
    onPlay: onPlay,
    onAddToQueue: onAddToQueue,
    onDownload: onDownload,
    onTogglePin: onTogglePin,
    onSelectMultiple: onSelectMultiple,
    header: AriamiSheetHeader(
      title: playlist.name,
      subtitle:
          '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
      leading: PlaylistCoverArt(
        playlist: playlist,
        size: 44,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}
