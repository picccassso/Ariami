import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/stats_range.dart';
import 'package:flutter/material.dart';

import '../../../../services/listening_stats_controller.dart';
import '../../../../services/player_api_client.dart';
import '../../../../theme/player_theme.dart';
import '../../../artwork.dart';
import '../playtime_format.dart';

enum StatsShareMode { tracks, artists, albums, combined }

enum StatsShareThemeMode { cover, dark, light }

typedef StatsOverviewMetric = ({String label, String value});

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

class StatsShareSnapshot {
  const StatsShareSnapshot({
    required this.range,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.totalSongsCount,
    required this.totalArtistsCount,
    required this.totalAlbumsCount,
    required this.totalListenedMs,
    required this.averageDailyMs,
    required this.playtimeUnit,
    required this.client,
  });

  final StatsRange range;
  final List<ListeningSongRollup> songs;
  final List<ListeningArtistStat> artists;
  final List<ListeningAlbumStat> albums;
  final int totalSongsCount;
  final int totalArtistsCount;
  final int totalAlbumsCount;
  final int totalListenedMs;
  final int averageDailyMs;
  final PlaytimeUnit playtimeUnit;
  final PlayerApiClient? client;

  bool get hasData =>
      songs.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty;

  bool hasDataFor(StatsShareMode mode) => switch (mode) {
        StatsShareMode.tracks => songs.isNotEmpty,
        StatsShareMode.artists => artists.isNotEmpty,
        StatsShareMode.albums => albums.isNotEmpty,
        StatsShareMode.combined => hasData,
      };

  ({String? albumId, String? songId})? primaryArtworkFor(StatsShareMode mode) {
    ({String? albumId, String? songId})? resolve(
      String? rawAlbumId, [
      String? rawSongId,
    ]) {
      final albumId = _nonEmpty(rawAlbumId);
      final songId = _nonEmpty(rawSongId);
      if (albumId == null && songId == null) return null;
      return (albumId: albumId, songId: songId);
    }

    switch (mode) {
      case StatsShareMode.tracks:
        return songs.isNotEmpty
            ? resolve(songs.first.albumId, songs.first.songId)
            : null;
      case StatsShareMode.artists:
        return artists.isNotEmpty
            ? resolve(
                artists.first.artworkAlbumId,
                artists.first.artworkSongId,
              )
            : null;
      case StatsShareMode.albums:
        return albums.isNotEmpty ? resolve(albums.first.albumId) : null;
      case StatsShareMode.combined:
        if (songs.isNotEmpty) {
          final art = resolve(songs.first.albumId, songs.first.songId);
          if (art != null) return art;
        }
        if (artists.isNotEmpty) {
          final art = resolve(
            artists.first.artworkAlbumId,
            artists.first.artworkSongId,
          );
          if (art != null) return art;
        }
        if (albums.isNotEmpty) {
          final art = resolve(albums.first.albumId);
          if (art != null) return art;
        }
        return null;
    }
  }

  List<StatsOverviewMetric> overviewMetricsFor(StatsShareMode mode) {
    final (countLabel, count) = switch (mode) {
      StatsShareMode.artists => ('Artists', totalArtistsCount),
      StatsShareMode.albums => ('Albums', totalAlbumsCount),
      StatsShareMode.tracks ||
      StatsShareMode.combined =>
        ('Tracks', totalSongsCount),
    };
    return [
      (label: countLabel, value: '$count'),
      (label: 'Playtime', value: _formatPlaytime(totalListenedMs)),
      (label: 'Daily average', value: _formatPlaytime(averageDailyMs)),
    ];
  }

  String _formatPlaytime(int milliseconds) => switch (playtimeUnit) {
        PlaytimeUnit.hours => formatListeningTime(milliseconds),
        PlaytimeUnit.minutes => formatListeningMinutes(milliseconds),
        PlaytimeUnit.minutesCompact =>
          formatListeningMinutesCompact(milliseconds),
      };
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
    final metrics = snapshot.overviewMetricsFor(mode);
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

    // Propagate the card's chosen theme so Artwork placeholders match light/cover cards.
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: <ThemeExtension<dynamic>>[colors],
      ),
      child: Container(
        width: cardWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: colors.groundGradient,
          borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
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
                        style: PlayerTheme.heading(
                          13,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: PlayerTheme.display(
                          36,
                          color: colors.textPrimary,
                        ),
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
                                style: PlayerTheme.display(
                                  28,
                                  color: colors.textPrimary,
                                ).copyWith(fontFeatures: PlayerTheme.tabular),
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
                        style: PlayerTheme.heading(
                          13,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        footerDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                          fontFeatures: PlayerTheme.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
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
            client: snapshot.client,
            albumId: _nonEmpty(song.albumId),
            songId: _nonEmpty(song.songId),
            title: song.songTitle ?? 'Unknown Track',
            subtitle: song.songArtist ?? 'Unknown Artist',
            playCount: song.playCount,
            formattedTime: formatListeningTime(song.listenedMs),
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
            client: snapshot.client,
            albumId: _nonEmpty(artist.artworkAlbumId),
            songId: _nonEmpty(artist.artworkSongId),
            placeholderIcon: Icons.person_rounded,
            title: artist.name,
            subtitle: artist.uniqueSongs > 0
                ? '${artist.uniqueSongs} '
                    '${artist.uniqueSongs == 1 ? 'track' : 'tracks'}'
                : '${artist.playCount} '
                    '${artist.playCount == 1 ? 'play' : 'plays'}',
            playCount: artist.playCount,
            formattedTime: formatListeningTime(artist.listenedMs),
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
            client: snapshot.client,
            albumId: _nonEmpty(album.albumId),
            title: album.title,
            subtitle: album.artist,
            playCount: album.playCount,
            formattedTime: formatListeningTime(album.listenedMs),
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
    required this.client,
    required this.title,
    required this.subtitle,
    required this.playCount,
    required this.formattedTime,
    required this.colors,
    this.albumId,
    this.songId,
    this.placeholderIcon = Icons.album_rounded,
  });

  final int rank;
  final PlayerApiClient? client;
  final String? albumId;
  final String? songId;
  final String title;
  final String subtitle;
  final int playCount;
  final String formattedTime;
  final PlayerColors colors;
  final IconData placeholderIcon;

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
              fontFeatures: PlayerTheme.tabular,
            ),
          ),
        ),
        Artwork(
          client: client,
          albumId: albumId,
          songId: songId,
          size: 38,
          borderRadius: PlayerTheme.coverRadius,
          placeholderIcon: placeholderIcon,
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
                fontFeatures: PlayerTheme.tabular,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: 10.5,
                color: colors.textSecondary,
                fontFeatures: PlayerTheme.tabular,
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
                  style: PlayerTheme.heading(13, color: colors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < topSongs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _CombinedTrackRow(
                    rank: i + 1,
                    client: snapshot.client,
                    stat: topSongs[i],
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
                          style: PlayerTheme.heading(
                            13,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < topArtists.length; i++) ...[
                          if (i > 0) const SizedBox(height: 7),
                          _CompactColumnRow(
                            rank: i + 1,
                            client: snapshot.client,
                            albumId: _nonEmpty(topArtists[i].artworkAlbumId),
                            songId: _nonEmpty(topArtists[i].artworkSongId),
                            placeholderIcon: Icons.person_rounded,
                            label: topArtists[i].name,
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
                          style: PlayerTheme.heading(
                            13,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < topAlbums.length; i++) ...[
                          if (i > 0) const SizedBox(height: 7),
                          _CompactColumnRow(
                            rank: i + 1,
                            client: snapshot.client,
                            albumId: _nonEmpty(topAlbums[i].albumId),
                            label: topAlbums[i].title,
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
    required this.client,
    required this.stat,
    required this.colors,
  });

  final int rank;
  final PlayerApiClient? client;
  final ListeningSongRollup stat;
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
              fontFeatures: PlayerTheme.tabular,
            ),
          ),
        ),
        Artwork(
          client: client,
          albumId: _nonEmpty(stat.albumId),
          songId: _nonEmpty(stat.songId),
          size: 32,
          borderRadius: PlayerTheme.coverRadius,
          placeholderIcon: Icons.album_rounded,
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
          '${stat.playCount}p · ${formatListeningTime(stat.listenedMs)}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
            fontFeatures: PlayerTheme.tabular,
          ),
        ),
      ],
    );
  }
}

class _CompactColumnRow extends StatelessWidget {
  const _CompactColumnRow({
    required this.rank,
    required this.client,
    required this.label,
    required this.playCount,
    required this.colors,
    this.albumId,
    this.songId,
    this.placeholderIcon = Icons.album_rounded,
  });

  final int rank;
  final PlayerApiClient? client;
  final String? albumId;
  final String? songId;
  final String label;
  final int playCount;
  final PlayerColors colors;
  final IconData placeholderIcon;

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
              fontFeatures: PlayerTheme.tabular,
            ),
          ),
        ),
        Artwork(
          client: client,
          albumId: albumId,
          songId: songId,
          size: 24,
          borderRadius: PlayerTheme.coverRadius,
          placeholderIcon: placeholderIcon,
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
            fontFeatures: PlayerTheme.tabular,
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
