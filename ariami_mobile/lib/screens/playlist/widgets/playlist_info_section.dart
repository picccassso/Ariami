import 'package:flutter/material.dart';
import '../../../models/api_models.dart';
import '../utils/playlist_helpers.dart';
import '../../../widgets/common/sleeve_header.dart';

class PlaylistInfoSection extends StatelessWidget {
  final PlaylistModel playlist;

  final List<SongModel> songs;

  const PlaylistInfoSection({
    super.key,
    required this.playlist,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final songCount = songs.isNotEmpty ? songs.length : playlist.songIds.length;
    final totalDuration = songs.isNotEmpty
        ? songs.fold<int>(0, (sum, s) => sum + s.duration)
        : playlist.songIds.fold<int>(
            0,
            (sum, songId) => sum + (playlist.songDurations[songId] ?? 0),
          );
    final formattedDuration = formatPlaylistTotalDuration(totalDuration);

    final description = playlist.description;
    return SleeveTitle(
      title: playlist.name,
      subtitle: description != null && description.isNotEmpty
          ? Text(description, style: SleeveTitle.subtitleStyle(context))
          : null,
      meta: 'Playlist, $songCount song${songCount != 1 ? 's' : ''}, '
          '$formattedDuration, created ${_formatDate(playlist.createdAt)}',
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7} weeks ago';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30} months ago';
    return '${diff.inDays ~/ 365} years ago';
  }
}
