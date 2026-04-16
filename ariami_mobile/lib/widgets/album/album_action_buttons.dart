import 'package:flutter/material.dart';

/// Row of album-level actions (download, queue, shuffle, play).
class AlbumActionButtons extends StatelessWidget {
  final bool isAlbumFullyDownloaded;
  final bool hasSongs;
  final VoidCallback? onDownloadAlbum;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onAddToQueue;
  final VoidCallback onShuffleAll;
  final VoidCallback onPlayAll;

  const AlbumActionButtons({
    super.key,
    required this.isAlbumFullyDownloaded,
    required this.hasSongs,
    required this.onDownloadAlbum,
    required this.onAddToPlaylist,
    required this.onAddToQueue,
    required this.onShuffleAll,
    required this.onPlayAll,
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
              IconButton(
                icon: Icon(
                  isAlbumFullyDownloaded
                      ? Icons.download_done_rounded
                      : Icons.download_for_offline_outlined,
                  color: isAlbumFullyDownloaded ? Colors.green : null,
                ),
                onPressed: onDownloadAlbum,
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
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: hasSongs ? onShuffleAll : null,
                iconSize: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: Colors.black,
                  iconSize: 36,
                  onPressed: hasSongs ? onPlayAll : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
