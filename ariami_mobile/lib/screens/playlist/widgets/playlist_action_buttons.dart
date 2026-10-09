import 'package:flutter/material.dart';
import '../../../widgets/collection_play_buttons.dart';
import '../../../widgets/download/collection_download_button.dart';

class PlaylistActionButtons extends StatelessWidget {
  /// Identifies this playlist as a playback source, so its Play button can
  /// show what's playing when the user has asked for that. Imported playlists
  /// must pass the server's id — that is what other devices publish.
  final String sourceId;

  final bool isPlaylistFullyDownloaded;

  final bool hasSongs;

  final bool canReorder;

  final bool isReorderMode;

  /// Song IDs used to calculate live collection download progress.
  final List<String> songIds;

  /// Starts a download or removes an already-downloaded playlist.
  final VoidCallback? onDownloadPlaylist;

  /// Cancels and removes an in-progress playlist download.
  final VoidCallback? onCancelDownload;

  final VoidCallback? onPlay;

  final VoidCallback? onShuffle;

  final VoidCallback? onToggleReorder;

  final VoidCallback? onAddSongs;

  final VoidCallback? onMoreActions;

  const PlaylistActionButtons({
    super.key,
    required this.sourceId,
    required this.isPlaylistFullyDownloaded,
    required this.hasSongs,
    required this.canReorder,
    required this.isReorderMode,
    this.songIds = const [],
    this.onDownloadPlaylist,
    this.onCancelDownload,
    this.onPlay,
    this.onShuffle,
    this.onToggleReorder,
    this.onAddSongs,
    this.onMoreActions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CollectionDownloadButton(
                songIds: songIds,
                isFullyDownloaded: isPlaylistFullyDownloaded,
                onPressed: onDownloadPlaylist,
                onCancel: onCancelDownload,
                collectionLabel: 'playlist',
                iconSize: 28,
              ),
              IconButton(
                icon: Icon(
                  isReorderMode ? Icons.check_rounded : Icons.reorder_rounded,
                  color: isReorderMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: canReorder ? onToggleReorder : null,
                iconSize: 28,
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: onAddSongs,
                iconSize: 28,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: onMoreActions,
                iconSize: 28,
                tooltip: 'More actions',
              ),
            ],
          ),

          Row(
            children: [
              CollectionShuffleButton(
                sourceId: sourceId,
                onShuffle: hasSongs ? onShuffle : null,
              ),
              const SizedBox(width: 8),
              CollectionPlayButton(
                sourceId: sourceId,
                onPlay: hasSongs ? onPlay : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
