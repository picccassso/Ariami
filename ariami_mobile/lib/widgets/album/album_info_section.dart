import 'package:flutter/material.dart';

/// Album information section shown above the track list.
class AlbumInfoSection extends StatelessWidget {
  final String albumTitle;
  final String albumArtist;
  final String? year;
  final int songCount;
  final int totalDurationSeconds;

  const AlbumInfoSection({
    super.key,
    required this.albumTitle,
    required this.albumArtist,
    required this.year,
    required this.songCount,
    required this.totalDurationSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            albumTitle,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            albumArtist,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (year != null) ...[
                Text(
                  year!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 8),
                Text('•', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(width: 8),
              ],
              Text(
                '$songCount ${songCount == 1 ? 'song' : 'songs'}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 8),
              Text('•', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(width: 8),
              Text(
                _formatDuration(totalDurationSeconds),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }
}
