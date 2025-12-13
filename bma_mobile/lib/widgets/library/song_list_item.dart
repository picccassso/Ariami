import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/playback_manager.dart';
import '../../services/download/download_manager.dart';
import '../../services/api/connection_service.dart';

/// Song list item widget
/// Displays song title, artist, and duration in a list row
class SongListItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isDownloaded;
  final bool isCached;
  final bool isAvailable;

  const SongListItem({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.isDownloaded = false,
    this.isCached = false,
    this.isAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    // Apply opacity when song is not available (offline and not downloaded)
    final opacity = isAvailable ? 1.0 : 0.5;

    return Opacity(
      opacity: opacity,
      child: InkWell(
        onTap: isAvailable ? onTap : null,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              // Offline availability indicator
              if (isDownloaded) ...[
                // Downloaded (protected) - green checkmark
                Icon(
                  Icons.download_done,
                  size: 16,
                  color: Colors.green[600],
                ),
                const SizedBox(width: 8),
              ] else if (isCached) ...[
                // Cached (may be evicted) - blue/grey cloud
                Icon(
                  Icons.cloud_done,
                  size: 16,
                  color: Colors.blue[400],
                ),
                const SizedBox(width: 8),
              ],
              // Song info (title and artist)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Song title
                    Text(
                      song.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isAvailable ? null : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Artist name
                    Text(
                      song.artist,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Duration
              Text(
                _formatDuration(song.duration),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              // Overflow menu button
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showSongMenu(context),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Format duration in seconds to mm:ss
  String _formatDuration(int durationInSeconds) {
    final minutes = durationInSeconds ~/ 60;
    final seconds = durationInSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Show song overflow menu
  void _showSongMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play'),
                onTap: onTap != null
                    ? () {
                        Navigator.pop(context);
                        onTap?.call();
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: const Text('Play Next'),
                onTap: () {
                  Navigator.pop(context);
                  _handlePlayNext(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to Queue'),
                onTap: () {
                  Navigator.pop(context);
                  _handleAddToQueue(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to Playlist'),
                onTap: () {
                  Navigator.pop(context);
                  AddToPlaylistScreen.showForSong(
                    context,
                    song.id,
                    albumId: song.albumId,
                    title: song.title,
                    artist: song.artist,
                    duration: song.duration,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Go to Artist'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Artist view (future feature)
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  _handleDownload(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Handle play next action
  void _handlePlayNext(BuildContext context) {
    final playbackManager = PlaybackManager();

    // Convert SongModel to Song object
    final convertedSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: null,
      albumId: song.albumId,
      duration: Duration(seconds: song.duration),
      filePath: song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: song.trackNumber,
    );

    playbackManager.playNext(convertedSong);
  }

  /// Handle add to queue action
  void _handleAddToQueue(BuildContext context) {
    final playbackManager = PlaybackManager();

    // Convert SongModel to Song object
    final convertedSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: null,
      albumId: song.albumId,
      duration: Duration(seconds: song.duration),
      filePath: song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: song.trackNumber,
    );

    playbackManager.addToQueue(convertedSong);
  }

  /// Handle download action
  void _handleDownload(BuildContext context) {
    final connectionService = ConnectionService();
    final downloadManager = DownloadManager();

    // Check if connected to server
    if (connectionService.apiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to server')),
      );
      return;
    }

    // Construct download URL using actual server connection
    final downloadUrl = '${connectionService.apiClient!.baseUrl}/download/${song.id}';

    downloadManager.downloadSong(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      albumArt: '',
      downloadUrl: downloadUrl,
      duration: song.duration,
      trackNumber: song.trackNumber,
      totalBytes: 0, // Will be determined during download
    );
  }
}
