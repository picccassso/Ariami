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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('LISTENING STATS'),
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: isDark ? Colors.white : Colors.black),
            onPressed: _showResetDialog,
            tooltip: 'Reset statistics',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? Colors.white : Colors.black,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: isDark ? Colors.white : Colors.black,
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'TRACKS'),
            Tab(text: 'ARTISTS'),
            Tab(text: 'ALBUMS'),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: isDark ? Colors.white : Colors.black,
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        onRefresh: () async {
          setState(() {});
        },
        child: Column(
          children: [
            // Overview card with totals (dynamic based on tab)
            _buildOverviewCard(),

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
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
            metric1Label = 'SONGS';
            metric1Value = stats.totalSongsPlayed.toString();
            metric2Label = 'PLAYTIME';
            metric2Value = _formatDurationShort(stats.totalTimeStreamed);
            metric3Label = 'AVG DAILY';
            metric3Value = _formatDurationShort(avgData.perCalendarDay);
            break;

          case 1: // Artists
            final avgData = _statsService.getAverageDailyTime();
            final artists = _statsService.getTopArtists(limit: 1000);
            final totalTime = artists.fold<Duration>(
              Duration.zero,
              (sum, artist) => sum + artist.totalTime,
            );
            metric1Label = 'ARTISTS';
            metric1Value = artists.length.toString();
            metric2Label = 'PLAYTIME';
            metric2Value = _formatDurationShort(totalTime);
            metric3Label = 'AVG DAILY';
            metric3Value = _formatDurationShort(avgData.perCalendarDay);
            break;

          case 2: // Albums
            final avgData = _statsService.getAverageDailyTime();
            final albums = _statsService.getTopAlbums(limit: 1000);
            final totalTime = albums.fold<Duration>(
              Duration.zero,
              (sum, album) => sum + album.totalTime,
            );
            metric1Label = 'ALBUMS';
            metric1Value = albums.length.toString();
            metric2Label = 'PLAYTIME';
            metric2Value = _formatDurationShort(totalTime);
            metric3Label = 'AVG DAILY';
            metric3Value = _formatDurationShort(avgData.perCalendarDay);
            break;

          default:
            metric1Label = 'SONGS';
            metric1Value = '0';
            metric2Label = 'PLAYTIME';
            metric2Value = '0h';
            metric3Label = 'AVG';
            metric3Value = '0m';
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111111) : const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(label: metric1Label, value: metric1Value, isDark: isDark),
                _buildStatItem(label: metric2Label, value: metric2Value, isDark: isDark),
                _buildStatItem(label: metric3Label, value: metric3Value, isDark: isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDurationShort(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  /// Build a single stat item in the grid
  Widget _buildStatItem({
    required String label,
    required String value,
    required bool isDark,
    String? secondaryValue,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            letterSpacing: 1.0,
          ),
        ),
        if (secondaryValue != null) ...[
          const SizedBox(height: 4),
          Text(
            secondaryValue,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[700] : Colors.grey[400],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Build the tracks tab
  Widget _buildTracksTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'TOP SONGS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'TOP ARTISTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'TOP ALBUMS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: isDark ? Colors.grey[800] : Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
             'Error loading statistics',
             style: TextStyle(
               fontSize: 14,
               fontWeight: FontWeight.w700,
               color: isDark ? Colors.grey[600] : Colors.grey[400],
             ),
          ),
        ],
      ),
    );
  }

  /// Build reusable loading state
  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: CircularProgressIndicator(
        color: isDark ? Colors.white : Colors.black,
        strokeWidth: 2,
      ),
    );
  }

  /// Build reusable empty state
  Widget _buildEmptyState(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note_rounded, size: 48, color: isDark ? Colors.grey[800] : Colors.grey[200]),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single top song item
  Widget _buildTopSongItem(SongStats stat, int rank) {
    final baseUrl = _connectionService.apiClient?.baseUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Prefer song-level artwork for individual tracks
    final artworkUrl = baseUrl != null ? '$baseUrl/song-artwork/${stat.songId}' : null;
    final cacheId = 'song_${stat.songId}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank number
          SizedBox(
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
          ),
          
          // Album artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: cacheId,
              artworkUrl: artworkUrl,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.songTitle ?? 'Unknown Track',
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
                  stat.songArtist ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${stat.playCount} PLAYS • ${stat.formattedTime.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    letterSpacing: 0.5,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String? artworkUrl;
    String cacheId;

    if (stat.randomAlbumId != null) {
      artworkUrl = baseUrl != null ? '$baseUrl/artwork/${stat.randomAlbumId}' : null;
      cacheId = stat.randomAlbumId!;
    } else if (stat.randomSongId != null) {
      artworkUrl = baseUrl != null ? '$baseUrl/song-artwork/${stat.randomSongId}' : null;
      cacheId = 'song_${stat.randomSongId}';
    } else {
      artworkUrl = null;
      cacheId = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank number
          SizedBox(
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
          ),

          // Artist artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: cacheId,
              artworkUrl: artworkUrl,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.artistName,
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
                  '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'SONG' : 'SONGS'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${stat.playCount} PLAYS • ${stat.formattedTime.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    letterSpacing: 0.5,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Rank number
          SizedBox(
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
          ),

          // Album artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedArtwork(
              albumId: stat.albumId,
              artworkUrl: baseUrl != null ? '$baseUrl/artwork/${stat.albumId}' : null,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.albumName ?? 'Unknown Album',
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
                  stat.albumArtist ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${stat.uniqueSongsCount} ${stat.uniqueSongsCount == 1 ? 'SONG' : 'SONGS'} • ${stat.formattedTime.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Show reset confirmation dialog
  void _showResetDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        title: Text(
          'RESET STATS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'This will permanently delete all your streaming statistics. This action cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
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
              'RESET',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: Color(0xFFFF4B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
