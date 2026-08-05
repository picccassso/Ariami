import 'package:flutter/material.dart';
import '../../services/playback_manager.dart';
import '../collection_play_buttons.dart';
import '../download/collection_download_button.dart';

/// Row of album-level actions (download, queue, shuffle, play).
class AlbumActionButtons extends StatelessWidget {
  /// Identifies this album as a playback source, so its Play button can show
  /// what's playing when the user has asked for that.
  final String albumId;
  final bool isAlbumFullyDownloaded;
  final bool hasSongs;
  final bool isPinned;
  final List<String> songIds;
  final VoidCallback? onDownloadAlbum;
  final VoidCallback? onCancelDownload;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onAddToQueue;
  final VoidCallback onShuffleAll;
  final VoidCallback onPlayAll;
  final VoidCallback onTogglePin;

  const AlbumActionButtons({
    super.key,
    required this.albumId,
    required this.isAlbumFullyDownloaded,
    required this.hasSongs,
    required this.isPinned,
    required this.songIds,
    required this.onDownloadAlbum,
    this.onCancelDownload,
    required this.onAddToPlaylist,
    required this.onAddToQueue,
    required this.onShuffleAll,
    required this.onPlayAll,
    required this.onTogglePin,
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
                isFullyDownloaded: isAlbumFullyDownloaded,
                onPressed: onDownloadAlbum,
                onCancel: onCancelDownload,
                collectionLabel: 'album',
                iconSize: 28,
              ),
              IconButton(
                icon: const Icon(Icons.playlist_add_rounded),
                onPressed: onAddToPlaylist,
                iconSize: 28,
              ),
              IconButton(
                icon: const Icon(Icons.queue_music_rounded),
                onPressed: onAddToQueue,
                iconSize: 28,
              ),
              IconButton(
                icon: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color:
                      isPinned ? Theme.of(context).colorScheme.primary : null,
                ),
                onPressed: onTogglePin,
                iconSize: 28,
                tooltip: isPinned ? 'Unpin album' : 'Pin album',
              ),
            ],
          ),
          Row(
            children: [
              CollectionShuffleButton(
                sourceId: PlaybackManager.albumSource(albumId),
                onShuffle: hasSongs ? onShuffleAll : null,
              ),
              const SizedBox(width: 8),
              CollectionPlayButton(
                sourceId: PlaybackManager.albumSource(albumId),
                onPlay: hasSongs ? onPlayAll : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
