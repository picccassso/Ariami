import 'package:flutter/material.dart';

import '../../../../models/album_stats.dart';
import '../../../../models/api_models.dart';
import '../../../../models/artist_stats.dart';
import '../../../../models/song_stats.dart';
import '../../../../services/stats/period_stats_loader.dart';
import '../../../../services/stats/stats_artwork_resolver.dart';
import '../../../../utils/constants.dart';
import '../../../../widgets/common/cached_artwork.dart';
import '../overview_metrics.dart';

enum StatsShareMode { tracks, artists, albums, combined }

enum StatsShareThemeMode { cover, dark, light }

class StatsShareSnapshot {
  const StatsShareSnapshot({
    required this.range,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.metricsForTab,
    required this.artworkResolver,
    required this.albumsById,
  });

  final StatsRange range;
  final List<SongStats> songs;
  final List<ArtistStats> artists;
  final List<AlbumStats> albums;
  final List<OverviewMetric> Function(int tabIndex) metricsForTab;
  final StatsArtworkResolver artworkResolver;
  final Map<String, AlbumModel> albumsById;

  bool get hasData =>
      songs.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty;

  bool hasDataFor(StatsShareMode mode) => switch (mode) {
        StatsShareMode.tracks => songs.isNotEmpty,
        StatsShareMode.artists => artists.isNotEmpty,
        StatsShareMode.albums => albums.isNotEmpty,
        StatsShareMode.combined => hasData,
      };

  StatsArtworkIdentity? primaryArtworkFor(StatsShareMode mode) {
    switch (mode) {
      case StatsShareMode.tracks:
        return songs.isNotEmpty ? artworkResolver.forSong(songs.first) : null;
      case StatsShareMode.artists:
        return artists.isNotEmpty
            ? artworkResolver.forArtist(artists.first)
            : null;
      case StatsShareMode.albums:
        return albums.isNotEmpty
            ? artworkResolver.forAlbum(albums.first)
            : null;
      case StatsShareMode.combined:
        if (songs.isNotEmpty) return artworkResolver.forSong(songs.first);
        if (artists.isNotEmpty) return artworkResolver.forArtist(artists.first);
        if (albums.isNotEmpty) return artworkResolver.forAlbum(albums.first);
        return null;
    }
  }
}

class StatsShareCard extends StatelessWidget {
  const StatsShareCard({
    super.key,
    required this.snapshot,
    required this.mode,
    required this.limit,
    required this.colors,
  });

  static const double cardWidth = 380;

  final StatsShareSnapshot snapshot;
  final StatsShareMode mode;
  final int limit;
  final PlayerColors colors;

  @override
  Widget build(BuildContext context) {
    final title = snapshot.range.title();
    final bounds = snapshot.range.bounds();
    final metrics = snapshot.metricsForTab(switch (mode) {
      StatsShareMode.artists => 1,
      StatsShareMode.albums => 2,
      StatsShareMode.tracks || StatsShareMode.combined => 0,
    });
    final categoryLabel = switch (mode) {
      StatsShareMode.tracks => 'Top tracks',
      StatsShareMode.artists => 'Top artists',
      StatsShareMode.albums => 'Top albums',
      StatsShareMode.combined => 'Listening summary',
    };
    final footerDate = bounds == null
        ? 'All time'
        : (bounds.from == bounds.to
            ? bounds.from
            : '${bounds.from} → ${bounds.to}');

    return Container(
      width: cardWidth,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: colors.groundGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CardGlowPainter(colors)),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryLabel,
                      style:
                          AppTheme.heading(13, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: AppTheme.display(36, color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final metric in metrics)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metric.value,
                              style: AppTheme.display(
                                28,
                                color: colors.textPrimary,
                              ).copyWith(fontFeatures: AppTheme.tabular),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              metric.label,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 266),
                child: _buildBody(),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.asset(
                        'assets/Ariami_icon.png',
                        width: 16,
                        height: 16,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ariami',
                      style: AppTheme.heading(13, color: colors.textPrimary),
                    ),
                    const Spacer(),
                    Text(
                      footerDate,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontFeatures: AppTheme.tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (mode) {
      case StatsShareMode.tracks:
        return _SingleListSection(
          items: snapshot.songs.take(limit).toList(),
          emptyText: 'No tracks in this period',
          colors: colors,
          itemBuilder: (song, rank) => _SingleRow(
            rank: rank,
            artwork: snapshot.artworkResolver.forSong(song),
            title: song.songTitle ?? 'Unknown Track',
            subtitle: song.songArtist ?? 'Unknown Artist',
            playCount: song.playCount,
            formattedTime: song.formattedTime,
            colors: colors,
          ),
        );
      case StatsShareMode.artists:
        return _SingleListSection(
          items: snapshot.artists.take(limit).toList(),
          emptyText: 'No artists in this period',
          colors: colors,
          itemBuilder: (artist, rank) => _SingleRow(
            rank: rank,
            artwork: snapshot.artworkResolver.forArtist(artist),
            fallbackIcon: Icons.person_rounded,
            title: artist.artistName,
            subtitle: artist.uniqueSongsCount > 0
                ? '${artist.uniqueSongsCount} '
                    '${artist.uniqueSongsCount == 1 ? 'song' : 'songs'}'
                : '${artist.playCount} '
                    '${artist.playCount == 1 ? 'play' : 'plays'}',
            playCount: artist.playCount,
            formattedTime: artist.formattedTime,
            colors: colors,
          ),
        );
      case StatsShareMode.albums:
        return _SingleListSection(
          items: snapshot.albums.take(limit).toList(),
          emptyText: 'No albums in this period',
          colors: colors,
          itemBuilder: (album, rank) => _SingleRow(
            rank: rank,
            artwork: snapshot.artworkResolver.forAlbum(album),
            title: album.albumName ??
                snapshot.albumsById[album.albumId]?.title ??
                'Unknown Album',
            subtitle: album.albumArtist ??
                snapshot.albumsById[album.albumId]?.artist ??
                'Unknown Artist',
            playCount: album.playCount,
            formattedTime: album.formattedTime,
            colors: colors,
          ),
        );
      case StatsShareMode.combined:
        return _CombinedBody(snapshot: snapshot, colors: colors);
    }
  }
}

class _SingleListSection<T> extends StatelessWidget {
  const _SingleListSection({
    required this.items,
    required this.emptyText,
    required this.colors,
    required this.itemBuilder,
  });

  final List<T> items;
  final String emptyText;
  final PlayerColors colors;
  final Widget Function(T item, int rank) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            itemBuilder(items[i], i + 1),
          ],
        ],
      ),
    );
  }
}

class _SingleRow extends StatelessWidget {
  const _SingleRow({
    required this.rank,
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.playCount,
    required this.formattedTime,
    required this.colors,
    this.fallbackIcon = Icons.album,
  });

  final int rank;
  final StatsArtworkIdentity artwork;
  final String title;
  final String subtitle;
  final int playCount;
  final String formattedTime;
  final PlayerColors colors;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.coverRadius),
          child: CachedArtwork(
            albumId: artwork.cacheId,
            artworkUrl: artwork.artworkUrl,
            width: 38,
            height: 38,
            fit: BoxFit.cover,
            fallbackIcon: fallbackIcon,
            fallbackIconSize: 18,
            sizeHint: ArtworkSizeHint.thumbnail,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$playCount ${playCount == 1 ? 'play' : 'plays'}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: AppTheme.tabular,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: 10.5,
                color: colors.textSecondary,
                fontFeatures: AppTheme.tabular,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CombinedBody extends StatelessWidget {
  const _CombinedBody({
    required this.snapshot,
    required this.colors,
  });

  final StatsShareSnapshot snapshot;
  final PlayerColors colors;

  @override
  Widget build(BuildContext context) {
    final topSongs = snapshot.songs.take(5).toList();
    final topArtists = snapshot.artists.take(5).toList();
    final topAlbums = snapshot.albums.take(5).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topSongs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top tracks',
                  style: AppTheme.heading(13, color: colors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < topSongs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _CombinedTrackRow(
                    rank: i + 1,
                    stat: topSongs[i],
                    artwork: snapshot.artworkResolver.forSong(topSongs[i]),
                    colors: colors,
                  ),
                ],
              ],
            ),
          ),
        if (topArtists.isNotEmpty || topAlbums.isNotEmpty) ...[
          if (topSongs.isNotEmpty)
            Divider(height: 1, thickness: 1, color: colors.border),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Top artists',
                          style:
                              AppTheme.heading(13, color: colors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < topArtists.length; i++) ...[
                          if (i > 0) const SizedBox(height: 7),
                          _CompactColumnRow(
                            rank: i + 1,
                            artwork: snapshot.artworkResolver
                                .forArtist(topArtists[i]),
                            fallbackIcon: Icons.person_rounded,
                            label: topArtists[i].artistName,
                            playCount: topArtists[i].playCount,
                            colors: colors,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: colors.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Top albums',
                          style:
                              AppTheme.heading(13, color: colors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < topAlbums.length; i++) ...[
                          if (i > 0) const SizedBox(height: 7),
                          _CompactColumnRow(
                            rank: i + 1,
                            artwork:
                                snapshot.artworkResolver.forAlbum(topAlbums[i]),
                            label: topAlbums[i].albumName ??
                                snapshot.albumsById[topAlbums[i].albumId]
                                    ?.title ??
                                'Unknown Album',
                            playCount: topAlbums[i].playCount,
                            colors: colors,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CombinedTrackRow extends StatelessWidget {
  const _CombinedTrackRow({
    required this.rank,
    required this.stat,
    required this.artwork,
    required this.colors,
  });

  final int rank;
  final SongStats stat;
  final StatsArtworkIdentity artwork;
  final PlayerColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.coverRadius),
          child: CachedArtwork(
            albumId: artwork.cacheId,
            artworkUrl: artwork.artworkUrl,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            fallbackIconSize: 16,
            sizeHint: ArtworkSizeHint.thumbnail,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.songTitle ?? 'Unknown Track',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                stat.songArtist ?? 'Unknown Artist',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${stat.playCount}p · ${stat.formattedTime}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
            fontFeatures: AppTheme.tabular,
          ),
        ),
      ],
    );
  }
}

class _CompactColumnRow extends StatelessWidget {
  const _CompactColumnRow({
    required this.rank,
    required this.artwork,
    required this.label,
    required this.playCount,
    required this.colors,
    this.fallbackIcon = Icons.album,
  });

  final int rank;
  final StatsArtworkIdentity artwork;
  final String label;
  final int playCount;
  final PlayerColors colors;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.coverRadius),
          child: CachedArtwork(
            albumId: artwork.cacheId,
            artworkUrl: artwork.artworkUrl,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            fallbackIcon: fallbackIcon,
            fallbackIconSize: 13,
            sizeHint: ArtworkSizeHint.thumbnail,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${playCount}p',
          style: TextStyle(
            fontSize: 10.5,
            color: colors.textSecondary,
            fontFeatures: AppTheme.tabular,
          ),
        ),
      ],
    );
  }
}

class _CardGlowPainter extends CustomPainter {
  const _CardGlowPainter(this.colors);

  final PlayerColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final glows = [
      (center: Offset.zero, radius: size.width * 0.85, color: colors.glowA),
      (
        center: Offset(size.width, size.height),
        radius: size.width * 0.85,
        color: colors.glowB,
      ),
    ];
    for (final glow in glows) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glow.color.withValues(alpha: 0.35),
              glow.color.withValues(alpha: 0.12),
              glow.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(
            Rect.fromCircle(center: glow.center, radius: glow.radius),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_CardGlowPainter old) => old.colors != colors;
}
