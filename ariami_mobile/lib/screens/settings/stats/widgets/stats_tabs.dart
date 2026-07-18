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

/// Lazily builds one stats tab list: the section title followed by one tile
/// per entry. Only the visible tiles are ever constructed, which keeps
/// uncapped lists scrolling smoothly.
Widget _rankedListView({
  required String title,
  required int itemCount,
  required Widget Function(BuildContext context, int index) itemBuilder,
}) {
  return ListView.builder(
    padding: const EdgeInsets.only(bottom: _listBottomInset),
    itemCount: itemCount + 1,
    itemBuilder: (context, index) {
      if (index == 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_SectionTitle(title), const SizedBox(height: 8)],
        );
      }
      return itemBuilder(context, index - 1);
    },
  );
}

/// A scrollable state view (loading/empty/error) under the section title, so
/// pull-to-refresh keeps working when there are no tiles.
Widget _statusListView(String title, Widget status) {
  return ListView(
    padding: const EdgeInsets.only(bottom: _listBottomInset),
    children: [_SectionTitle(title), const SizedBox(height: 8), status],
  );
}

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
    return StreamBuilder<List<SongStats>>(
      stream: statsService.topSongsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusListView('TOP SONGS', const StatsErrorState());
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _statusListView('TOP SONGS', const StatsLoadingState());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _statusListView(
            'TOP SONGS',
            const StatsEmptyState(
                'No stats yet. Start listening to see your top songs!'),
          );
        }

        final topSongs = snapshot.data!;
        return _rankedListView(
          title: 'TOP SONGS',
          itemCount: topSongs.length,
          itemBuilder: (context, index) => TopSongTile(
            stat: topSongs[index],
            rank: index + 1,
            artworkResolver: artworkResolver,
          ),
        );
      },
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
    if (credited != null) {
      if (credited.isEmpty) {
        return _statusListView(
          'TOP ARTISTS',
          const StatsEmptyState(
              'No stats yet. Start listening to see your top artists!'),
        );
      }
      return _rankedListView(
        title: 'TOP ARTISTS',
        itemCount: credited.length,
        itemBuilder: (context, index) => TopArtistTile(
          stat: credited[index],
          rank: index + 1,
          artworkResolver: artworkResolver,
        ),
      );
    }

    return StreamBuilder<List<ArtistStats>>(
      stream: statsService.topArtistsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusListView('TOP ARTISTS', const StatsErrorState());
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _statusListView('TOP ARTISTS', const StatsLoadingState());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _statusListView(
            'TOP ARTISTS',
            const StatsEmptyState(
                'No stats yet. Start listening to see your top artists!'),
          );
        }

        final topArtists = snapshot.data!;
        return _rankedListView(
          title: 'TOP ARTISTS',
          itemCount: topArtists.length,
          itemBuilder: (context, index) => TopArtistTile(
            stat: topArtists[index],
            rank: index + 1,
            artworkResolver: artworkResolver,
          ),
        );
      },
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
    return StreamBuilder<List<AlbumStats>>(
      stream: statsService.topAlbumsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusListView('TOP ALBUMS', const StatsErrorState());
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _statusListView('TOP ALBUMS', const StatsLoadingState());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _statusListView(
            'TOP ALBUMS',
            const StatsEmptyState(
                'No stats yet. Start listening to see your top albums!'),
          );
        }

        final topAlbums = snapshot.data!;
        return _rankedListView(
          title: 'TOP ALBUMS',
          itemCount: topAlbums.length,
          itemBuilder: (context, index) => TopAlbumTile(
            stat: topAlbums[index],
            rank: index + 1,
            artworkResolver: artworkResolver,
            albumsById: albumsById,
          ),
        );
      },
    );
  }
}

/// One tab (0=tracks, 1=artists, 2=albums) for a server-derived period.
class StatsPeriodTab extends StatefulWidget {
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
  State<StatsPeriodTab> createState() => _StatsPeriodTabState();
}

class _StatsPeriodTabState extends State<StatsPeriodTab> {
  /// Adapting rollups to display models — the credited-artist matching in
  /// particular — is heavy on uncapped lists, so it runs once per fetched
  /// period instead of on every rebuild.
  ListeningPeriodStats? _adaptedFor;
  List<SongStats> _songs = const <SongStats>[];
  List<ArtistStats> _artists = const <ArtistStats>[];
  List<AlbumStats> _albums = const <AlbumStats>[];

  void _ensureAdapted(ListeningPeriodStats stats) {
    if (identical(_adaptedFor, stats)) return;
    _adaptedFor = stats;
    switch (widget.tab) {
      case 1:
        _artists = artistStatsFromCredited(
          stats.artists,
          songStatsFromRollups(stats.songs),
        );
      case 2:
        _albums = albumStatsFromRollups(stats.albums);
      default:
        _songs = songStatsFromRollups(stats.songs);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.stats == null) {
      return const StatsLoadingState();
    }
    if (widget.unavailable) {
      return const StatsEmptyState(
        'Stats for this period need a connection to your server '
        '(and a server that supports period stats).',
        icon: Icons.cloud_off_rounded,
      );
    }
    final periodStats = widget.stats;
    if (periodStats == null) return const StatsLoadingState();
    _ensureAdapted(periodStats);

    final title = switch (widget.tab) {
      1 => 'TOP ARTISTS',
      2 => 'TOP ALBUMS',
      _ => 'TOP SONGS',
    };
    final itemCount = switch (widget.tab) {
      1 => _artists.length,
      2 => _albums.length,
      _ => _songs.length,
    };

    if (itemCount == 0) {
      return ListView(
        padding: const EdgeInsets.only(bottom: _listBottomInset),
        children: const [
          SizedBox(height: 40),
          StatsEmptyState('No listening in this period yet.'),
        ],
      );
    }

    return _rankedListView(
      title: title,
      itemCount: itemCount,
      itemBuilder: (context, index) => switch (widget.tab) {
        1 => TopArtistTile(
            stat: _artists[index],
            rank: index + 1,
            artworkResolver: widget.artworkResolver,
          ),
        2 => TopAlbumTile(
            stat: _albums[index],
            rank: index + 1,
            artworkResolver: widget.artworkResolver,
            albumsById: widget.albumsById,
          ),
        _ => TopSongTile(
            stat: _songs[index],
            rank: index + 1,
            artworkResolver: widget.artworkResolver,
          ),
      },
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
