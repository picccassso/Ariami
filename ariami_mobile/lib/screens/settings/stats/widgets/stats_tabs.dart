import 'package:ariami_core/ariami_core.dart' show ListeningPeriodStats;
import 'package:flutter/material.dart';

import '../../../../models/album_stats.dart';
import '../../../../models/api_models.dart';
import '../../../../models/artist_stats.dart';
import '../../../../models/song_stats.dart';
import '../../../../services/stats/period_stats_loader.dart';
import '../../../../services/stats/stats_artwork_resolver.dart';
import '../../../../services/stats/streaming_stats_service.dart';
import 'stats_list_items.dart';
import 'stats_status_views.dart';

/// The scroll inset that keeps list content clear of the floating period
/// selector plus the global bottom chrome.
const double _listBottomInset = 240;

/// The all-time tracks tab.
class StatsTracksTab extends StatelessWidget {
  const StatsTracksTab({
    super.key,
    required this.statsService,
    required this.artworkResolver,
  });

  final StreamingStatsService statsService;
  final StatsArtworkResolver artworkResolver;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        const _SectionTitle('TOP SONGS'),
        const SizedBox(height: 8),
        StreamBuilder<List<SongStats>>(
          stream: statsService.topSongsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const StatsErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const StatsLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const StatsEmptyState(
                  'No stats yet. Start listening to see your top songs!');
            }

            final topSongs = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topSongs.length,
              itemBuilder: (context, index) => TopSongTile(
                stat: topSongs[index],
                rank: index + 1,
                artworkResolver: artworkResolver,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The all-time artists tab. Prefers the server's credited-artist rollups
/// (each collaborator on a multi-artist track counted individually) and
/// falls back to local combined-string grouping when unavailable.
class StatsArtistsTab extends StatelessWidget {
  const StatsArtistsTab({
    super.key,
    required this.statsService,
    required this.creditedArtists,
    required this.artworkResolver,
  });

  final StreamingStatsService statsService;

  /// All-time credited artists from the server; null means unavailable
  /// (offline / old server) and the local grouping is shown instead.
  final List<ArtistStats>? creditedArtists;
  final StatsArtworkResolver artworkResolver;

  @override
  Widget build(BuildContext context) {
    final credited = creditedArtists;
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        const _SectionTitle('TOP ARTISTS'),
        const SizedBox(height: 8),
        if (credited != null)
          credited.isEmpty
              ? const StatsEmptyState(
                  'No stats yet. Start listening to see your top artists!')
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: credited.length,
                  itemBuilder: (context, index) => TopArtistTile(
                    stat: credited[index],
                    rank: index + 1,
                    artworkResolver: artworkResolver,
                  ),
                )
        else
          StreamBuilder<List<ArtistStats>>(
            stream: statsService.topArtistsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const StatsErrorState();
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const StatsLoadingState();
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const StatsEmptyState(
                    'No stats yet. Start listening to see your top artists!');
              }

              final topArtists = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: topArtists.length,
                itemBuilder: (context, index) => TopArtistTile(
                  stat: topArtists[index],
                  rank: index + 1,
                  artworkResolver: artworkResolver,
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The all-time albums tab.
class StatsAlbumsTab extends StatelessWidget {
  const StatsAlbumsTab({
    super.key,
    required this.statsService,
    required this.artworkResolver,
    required this.albumsById,
  });

  final StreamingStatsService statsService;
  final StatsArtworkResolver artworkResolver;
  final Map<String, AlbumModel> albumsById;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        const _SectionTitle('TOP ALBUMS'),
        const SizedBox(height: 8),
        StreamBuilder<List<AlbumStats>>(
          stream: statsService.topAlbumsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const StatsErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const StatsLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const StatsEmptyState(
                  'No stats yet. Start listening to see your top albums!');
            }

            final topAlbums = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topAlbums.length,
              itemBuilder: (context, index) => TopAlbumTile(
                stat: topAlbums[index],
                rank: index + 1,
                artworkResolver: artworkResolver,
                albumsById: albumsById,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// One tab (0=tracks, 1=artists, 2=albums) for a server-derived period.
class StatsPeriodTab extends StatelessWidget {
  const StatsPeriodTab({
    super.key,
    required this.tab,
    required this.loading,
    required this.unavailable,
    required this.stats,
    required this.artworkResolver,
    required this.albumsById,
  });

  final int tab;
  final bool loading;
  final bool unavailable;
  final ListeningPeriodStats? stats;
  final StatsArtworkResolver artworkResolver;
  final Map<String, AlbumModel> albumsById;

  @override
  Widget build(BuildContext context) {
    if (loading && stats == null) {
      return const StatsLoadingState();
    }
    if (unavailable) {
      return const StatsEmptyState(
        'Stats for this period need a connection to your server '
        '(and a server that supports period stats).',
        icon: Icons.cloud_off_rounded,
      );
    }
    final periodStats = stats;
    if (periodStats == null) return const StatsLoadingState();

    final title = switch (tab) {
      1 => 'TOP ARTISTS',
      2 => 'TOP ALBUMS',
      _ => 'TOP SONGS',
    };
    final rows = switch (tab) {
      1 => [
          for (final (index, stat) in artistStatsFromCredited(
            periodStats.artists,
            songStatsFromRollups(periodStats.songs),
          ).indexed)
            TopArtistTile(
              stat: stat,
              rank: index + 1,
              artworkResolver: artworkResolver,
            ),
        ],
      2 => [
          for (final (index, stat)
              in albumStatsFromRollups(periodStats.albums).indexed)
            TopAlbumTile(
              stat: stat,
              rank: index + 1,
              artworkResolver: artworkResolver,
              albumsById: albumsById,
            ),
        ],
      _ => [
          for (final (index, stat)
              in songStatsFromRollups(periodStats.songs).indexed)
            TopSongTile(
              stat: stat,
              rank: index + 1,
              artworkResolver: artworkResolver,
            ),
        ],
    };

    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: _listBottomInset),
        children: const [
          SizedBox(height: 40),
          StatsEmptyState('No listening in this period yet.'),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      children: [
        _SectionTitle(title),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }
}

/// The "TOP SONGS" / "TOP ARTISTS" / "TOP ALBUMS" list header.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: isDark ? Colors.white : Colors.black,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
