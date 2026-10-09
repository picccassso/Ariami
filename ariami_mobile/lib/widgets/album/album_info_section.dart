import 'package:flutter/material.dart';
import 'package:ariami_core/utils/format.dart';

import '../common/artist_link.dart';

class AlbumInfoSection extends StatelessWidget {
  final String albumTitle;
  final String albumArtist;
  final String? year;
  final int songCount;
  final int totalDurationSeconds;
  final String? genre;

  const AlbumInfoSection({
    super.key,
    required this.albumTitle,
    required this.albumArtist,
    required this.year,
    required this.songCount,
    required this.totalDurationSeconds,
    this.genre,
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
          ArtistLink(
            name: albumArtist,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            [
              if (year != null) year!,
              '$songCount ${songCount == 1 ? 'song' : 'songs'}',
              formatHoursMinutes(totalDurationSeconds),
              if (genre != null) genre!,
            ].join(' • '),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
