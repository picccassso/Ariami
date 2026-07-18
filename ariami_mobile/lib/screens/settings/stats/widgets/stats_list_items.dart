import 'package:flutter/material.dart';

import '../../../../models/album_stats.dart';
import '../../../../models/api_models.dart';
import '../../../../models/artist_stats.dart';
import '../../../../models/song_stats.dart';
import '../../../../services/stats/stats_artwork_resolver.dart';
import '../../../../widgets/common/cached_artwork.dart';

/// A single top song item.
class TopSongTile extends StatelessWidget {
  const TopSongTile({
    super.key,
    required this.stat,
    required this.rank,
    required this.artworkResolver,
  });

  final SongStats stat;
  final int rank;
  final StatsArtworkResolver artworkResolver;

  @override
  Widget build(BuildContext context) {
    final artwork = artworkResolver.forSong(stat);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _RankNumber(rank: rank),

          // Album artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: artwork.cacheId,
              artworkUrl: artwork.artworkUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              fallbackIconSize: 24,
              sizeHint: ArtworkSizeHint.thumbnail,
            ),
          ),
          const SizedBox(width: 16),

          // Song info
          Expanded(
            child: _TileInfo(
              title: stat.songTitle ?? 'Unknown Track',
              subtitle: stat.songArtist ?? 'Unknown Artist',
              detail:
                  '${stat.playCount} PLAYS • ${stat.formattedTime.toUpperCase()}',
            ),
          ),
        ],
      ),
    );
  }
}

/// A single top artist item.
class TopArtistTile extends StatelessWidget {
  const TopArtistTile({
    super.key,
    required this.stat,
    required this.rank,
    required this.artworkResolver,
  });

  final ArtistStats stat;
  final int rank;
  final StatsArtworkResolver artworkResolver;

  @override
  Widget build(BuildContext context) {
    final artwork = artworkResolver.forArtist(stat);

    // Credited-artist rollups don't carry a song count; fall back to plays.
    final subtitle = stat.uniqueSongsCount > 0
        ? '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'SONG' : 'SONGS'}'
        : '${stat.playCount} ${stat.playCount == 1 ? 'PLAY' : 'PLAYS'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _RankNumber(rank: rank),

          // Artist artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: artwork.cacheId,
              artworkUrl: artwork.artworkUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              fallbackIcon: Icons.person_rounded,
              fallbackIconSize: 24,
              sizeHint: ArtworkSizeHint.thumbnail,
            ),
          ),
          const SizedBox(width: 16),

          // Artist info
          Expanded(
            child: _TileInfo(
              title: stat.artistName,
              subtitle: subtitle,
              subtitleEllipsis: false,
              detail:
                  '${stat.playCount} PLAYS • ${stat.formattedTime.toUpperCase()}',
            ),
          ),
        ],
      ),
    );
  }
}

/// A single top album item. Album name/artist fall back to the library's
/// metadata in [albumsById] when the stored stat doesn't carry them.
class TopAlbumTile extends StatelessWidget {
  const TopAlbumTile({
    super.key,
    required this.stat,
    required this.rank,
    required this.artworkResolver,
    required this.albumsById,
  });

  final AlbumStats stat;
  final int rank;
  final StatsArtworkResolver artworkResolver;
  final Map<String, AlbumModel> albumsById;

  @override
  Widget build(BuildContext context) {
    final artwork = artworkResolver.forAlbum(stat);
    // Period rollups don't carry a song count; fall back to plays.
    final detail = stat.uniqueSongsCount > 0
        ? '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'SONG' : 'SONGS'}'
        : '${stat.playCount} ${stat.playCount == 1 ? 'PLAY' : 'PLAYS'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _RankNumber(rank: rank),

          // Album artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: artwork.cacheId,
              artworkUrl: artwork.artworkUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              fallbackIconSize: 24,
              sizeHint: ArtworkSizeHint.thumbnail,
            ),
          ),
          const SizedBox(width: 16),

          // Album info
          Expanded(
            child: _TileInfo(
              title: stat.albumName ??
                  albumsById[stat.albumId]?.title ??
                  'Unknown Album',
              subtitle: stat.albumArtist ??
                  albumsById[stat.albumId]?.artist ??
                  'Unknown Artist',
              detail: '$detail • ${stat.formattedTime.toUpperCase()}',
            ),
          ),
        ],
      ),
    );
  }
}

/// The greyed rank number in the tile's left gutter.
class _RankNumber extends StatelessWidget {
  const _RankNumber({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 28,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: isDark ? Colors.grey[700] : Colors.grey[400],
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// The title / subtitle / detail column shared by all three tiles.
class _TileInfo extends StatelessWidget {
  const _TileInfo({
    required this.title,
    required this.subtitle,
    required this.detail,
    this.subtitleEllipsis = true,
  });

  final String title;
  final String subtitle;
  final String detail;

  /// The artist tile's subtitle ("N SONGS") never overflows and historically
  /// rendered without ellipsis; song/album subtitles keep it.
  final bool subtitleEllipsis;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
          ),
          maxLines: subtitleEllipsis ? 1 : null,
          overflow: subtitleEllipsis ? TextOverflow.ellipsis : null,
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[700] : Colors.grey[400],
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
