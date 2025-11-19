import 'package:flutter/material.dart';
import '../../models/api_models.dart';

/// Search result item for songs
class SearchResultSongItem extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final String? searchQuery;

  const SearchResultSongItem({
    super.key,
    required this.song,
    required this.onTap,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
        child: Icon(
          Icons.music_note,
          color: Theme.of(context).primaryColor,
        ),
      ),
      title: Text(
        song.title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.artist,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatDuration(song.duration),
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      ),
      onTap: onTap,
    );
  }

  /// Format duration in seconds to mm:ss
  String _formatDuration(int durationInSeconds) {
    final minutes = durationInSeconds ~/ 60;
    final seconds = durationInSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
