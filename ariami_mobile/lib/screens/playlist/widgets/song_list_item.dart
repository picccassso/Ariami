import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import '../../../services/api/connection_service.dart';
import '../utils/playlist_helpers.dart';
import 'album_art_with_badge.dart';

/// Normal song list item with dismissible action to remove
class SongListItem extends StatelessWidget {
  /// The song to display
  final SongModel song;

  /// Index in the list
  final int index;

  /// Whether the song is available for playback
  final bool isAvailable;

  /// Whether the song is downloaded
  final bool isDownloaded;

  /// Connection service for artwork
  final ConnectionService connectionService;

  /// Callback when song is tapped
  final VoidCallback? onTap;

  /// Callback when song is dismissed/removed
  final VoidCallback? onRemove;

  const SongListItem({
    super.key,
    required this.song,
    required this.index,
    required this.isAvailable,
    required this.isDownloaded,
    required this.connectionService,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = isAvailable ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: Dismissible(
        key: ValueKey('dismiss_${song.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => onRemove?.call(),
        child: ListTile(
          leading: AlbumArtWithBadge(
            song: song,
            isDownloaded: isDownloaded,
            connectionService: connectionService,
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isAvailable ? null : Colors.grey,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600]),
          ),
          trailing: Text(
            formatDuration(song.duration),
            style: TextStyle(color: Colors.grey[600]),
          ),
          onTap: isAvailable ? onTap : null,
        ),
      ),
    );
  }
}
