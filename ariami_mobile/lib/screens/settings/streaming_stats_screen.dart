import 'package:flutter/material.dart';
import '../../models/song_stats.dart';
import '../../models/artist_stats.dart';
import '../../models/album_stats.dart';
import '../../services/stats/streaming_stats_service.dart';
import '../../services/api/connection_service.dart';
import '../../widgets/common/cached_artwork.dart';

/// Screen displaying streaming statistics and listening data
class StreamingStatsScreen extends StatefulWidget {
  const StreamingStatsScreen({super.key});

  @override
  State<StreamingStatsScreen> createState() => _StreamingStatsScreenState();
}

class _StreamingStatsScreenState extends State<StreamingStatsScreen>
    with SingleTickerProviderStateMixin {
  final StreamingStatsService _statsService = StreamingStatsService();
  final ConnectionService _connectionService = ConnectionService();

  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    });
    // Request fresh data when screen loads
    _statsService.refreshTopSongs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _showResetDialog,
            tooltip: 'Reset statistics',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tracks'),
            Tab(text: 'Artists'),
            Tab(text: 'Albums'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh the UI
          setState(() {});
        },
        child: Column(
          children: [
            // Overview card with totals (dynamic based on tab)
            _buildOverviewCard(),
            const SizedBox(height: 16),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTracksTab(),
                  _buildArtistsTab(),
                  _buildAlbumsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the overview card showing total stats (dynamic based on tab)
  Widget _buildOverviewCard() {
    return ListenableBuilder(
      listenable: _statsService,
      builder: (context, _) {
        String metric1Label;
        String metric1Value;
        String metric2Label;
        String metric2Value;
        String metric3Label;
        String metric3Value;

        switch (_currentTabIndex) {
          case 0: // Tracks
            final stats = _statsService.getTotalStats();
            final avgData = _statsService.getAverageDailyTime();
            metric1Label = 'Songs Played';
            metric1Value = stats.totalSongsPlayed.toString();
            metric2Label = 'Total Time';
            metric2Value = _formatDuration(stats.totalTimeStreamed);
            metric3Label = 'Daily Avg';
            metric3Value = _formatDuration(avgData.perCalendarDay);
            break;

          case 1: // Artists
            final avgData = _statsService.getAverageDailyTime();
            final artists = _statsService.getTopArtists(limit: 1000);
            final totalTime = artists.fold<Duration>(
              Duration.zero,
              (sum, artist) => sum + artist.totalTime,
            );
            metric1Label = 'Artists Played';
            metric1Value = artists.length.toString();
            metric2Label = 'Total Time';
            metric2Value = _formatDuration(totalTime);
            metric3Label = 'Daily Avg';
            metric3Value = _formatDuration(avgData.perCalendarDay);
            break;

          case 2: // Albums
            final avgData = _statsService.getAverageDailyTime();
            final albums = _statsService.getTopAlbums(limit: 1000);
            final totalTime = albums.fold<Duration>(
              Duration.zero,
              (sum, album) => sum + album.totalTime,
            );
            metric1Label = 'Albums Played';
            metric1Value = albums.length.toString();
            metric2Label = 'Total Time';
            metric2Value = _formatDuration(totalTime);
            metric3Label = 'Daily Avg';
            metric3Value = _formatDuration(avgData.perCalendarDay);
            break;

          default:
            metric1Label = 'Songs Played';
            metric1Value = '0';
            metric2Label = 'Total Time';
            metric2Value = '0m';
            metric3Label = 'Daily Avg';
            metric3Value = '0m';
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Listening Stats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(label: metric1Label, value: metric1Value),
                      _buildStatItem(label: metric2Label, value: metric2Value),
                      _buildStatItem(label: metric3Label, value: metric3Value),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build a single stat item in the grid
  Widget _buildStatItem({
    required String label,
    required String value,
    String? secondaryValue,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        if (secondaryValue != null) ...[
          const SizedBox(height: 4),
          Text(
            secondaryValue,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Build the tracks tab
  Widget _buildTracksTab() {
    return ListView(
      padding: EdgeInsets.only(
        bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Your Top Songs',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<SongStats>>(
          stream: _statsService.topSongsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _buildLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState('No stats yet. Start listening to see your top songs!');
            }

            final topSongs = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topSongs.length,
              itemBuilder: (context, index) {
                final stat = topSongs[index];
                return _buildTopSongItem(stat, index + 1);
              },
            );
          },
        ),
      ],
    );
  }

  /// Build the artists tab
  Widget _buildArtistsTab() {
    return ListView(
      padding: EdgeInsets.only(
        bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Your Top Artists',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<ArtistStats>>(
          stream: _statsService.topArtistsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _buildLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState('No stats yet. Start listening to see your top artists!');
            }

            final topArtists = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topArtists.length,
              itemBuilder: (context, index) {
                final stat = topArtists[index];
                return _buildTopArtistItem(stat, index + 1);
              },
            );
          },
        ),
      ],
    );
  }

  /// Build the albums tab
  Widget _buildAlbumsTab() {
    return ListView(
      padding: EdgeInsets.only(
        bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Your Top Albums',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<AlbumStats>>(
          stream: _statsService.topAlbumsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _buildLoadingState();
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyState('No stats yet. Start listening to see your top albums!');
            }

            final topAlbums = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topAlbums.length,
              itemBuilder: (context, index) {
                final stat = topAlbums[index];
                return _buildTopAlbumItem(stat, index + 1);
              },
            );
          },
        ),
      ],
    );
  }

  /// Build reusable error state
  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Error loading stats',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build reusable loading state
  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// Build reusable empty state
  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a single top song item
  Widget _buildTopSongItem(SongStats stat, int rank) {
    final baseUrl = _connectionService.apiClient?.baseUrl;

    // Determine artwork URL and cache ID based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (stat.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = baseUrl != null ? '$baseUrl/artwork/${stat.albumId}' : null;
      cacheId = stat.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = baseUrl != null ? '$baseUrl/song-artwork/${stat.songId}' : null;
      cacheId = 'song_${stat.songId}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Album artwork (uses cache for offline support)
          CachedArtwork(
            albumId: cacheId, // Used as cache key
            artworkUrl: artworkUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(8),
            fallbackIconSize: 32,
          ),
          const SizedBox(width: 12),

          // Rank number
          SizedBox(
            width: 24,
            child: Text(
              '$rank.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Song info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.songTitle ?? 'Unknown Song',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  stat.songArtist ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${stat.playCount} ${stat.playCount == 1 ? 'play' : 'plays'} • ${stat.formattedTime}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single top artist item
  Widget _buildTopArtistItem(ArtistStats stat, int rank) {
    final baseUrl = _connectionService.apiClient?.baseUrl;

    // Determine artwork URL and cache ID
    // Prefer album artwork, fall back to song artwork for standalone songs
    String? artworkUrl;
    String cacheId;

    if (stat.randomAlbumId != null) {
      // Use album artwork
      artworkUrl = baseUrl != null ? '$baseUrl/artwork/${stat.randomAlbumId}' : null;
      cacheId = stat.randomAlbumId!;
    } else if (stat.randomSongId != null) {
      // Fallback to standalone song artwork
      artworkUrl = baseUrl != null ? '$baseUrl/song-artwork/${stat.randomSongId}' : null;
      cacheId = 'song_${stat.randomSongId}';
    } else {
      // No artwork available
      artworkUrl = null;
      cacheId = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Artist artwork (uses cache)
          CachedArtwork(
            albumId: cacheId, // Used as cache key
            artworkUrl: artworkUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(8),
            fallbackIcon: Icons.person,
            fallbackIconSize: 32,
          ),
          const SizedBox(width: 12),

          // Rank number
          SizedBox(
            width: 24,
            child: Text(
              '$rank.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Artist info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.artistName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'song' : 'songs'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${stat.playCount} ${stat.playCount == 1 ? 'play' : 'plays'} • ${stat.formattedTime}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single top album item
  Widget _buildTopAlbumItem(AlbumStats stat, int rank) {
    final baseUrl = _connectionService.apiClient?.baseUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Album artwork (uses cache)
          CachedArtwork(
            albumId: stat.albumId,
            artworkUrl: baseUrl != null
                ? '$baseUrl/artwork/${stat.albumId}'
                : null,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(8),
            fallbackIconSize: 32,
          ),
          const SizedBox(width: 12),

          // Rank number
          SizedBox(
            width: 24,
            child: Text(
              '$rank.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Album info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.albumName ?? 'Unknown Album',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  stat.albumArtist ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'song' : 'songs'} • ${stat.formattedTime}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Format duration as "1h 20m" or "20m"
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Show reset confirmation dialog
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Statistics'),
        content: const Text(
          'This will permanently delete all your streaming statistics. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _statsService.resetAllStats();
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
