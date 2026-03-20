import 'package:flutter/material.dart';
import '../../../models/api_models.dart';

/// Playlist information section showing name, description, and song stats
class PlaylistInfoSection extends StatelessWidget {
  /// The playlist model
  final PlaylistModel playlist;

  /// List of songs for duration calculation
  final List<SongModel> songs;

  const PlaylistInfoSection({
    super.key,
    required this.playlist,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    final totalDuration = songs.fold<int>(0, (sum, s) => sum + s.duration);
    final minutes = totalDuration ~/ 60;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            playlist.name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (playlist.description != null &&
              playlist.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              playlist.description!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${songs.length} song${songs.length != 1 ? 's' : ''} • $minutes min',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Created ${_formatDate(playlist.createdAt)}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
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
