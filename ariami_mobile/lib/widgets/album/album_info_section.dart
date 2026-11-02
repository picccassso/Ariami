import 'package:flutter/material.dart';
import 'package:ariami_core/utils/format.dart';

import '../common/artist_link.dart';
import '../common/sleeve_header.dart';

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
    return SleeveTitle(
      title: albumTitle,
      subtitle: ArtistLink(
        name: albumArtist,
        style: SleeveTitle.subtitleStyle(context),
      ),
      meta: [
        'Album',
        if (year != null) year!,
        '$songCount ${songCount == 1 ? 'song' : 'songs'}',
        formatHoursMinutes(totalDurationSeconds),
        if (genre != null) genre!,
      ].join(', '),
    );
  }
}
