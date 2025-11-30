import 'package:flutter/material.dart';
import '../../models/song_stats.dart';
import '../../services/stats/streaming_stats_service.dart';

/// Screen displaying streaming statistics and listening data
class StreamingStatsScreen extends StatefulWidget {
  const StreamingStatsScreen({super.key});

  @override
  State<StreamingStatsScreen> createState() => _StreamingStatsScreenState();
}

class _StreamingStatsScreenState extends State<StreamingStatsScreen> {
  final StreamingStatsService _statsService = StreamingStatsService();

  @override
  void initState() {
    super.initState();
    // Request fresh data when screen loads
    _statsService.refreshTopSongs();
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
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh the UI
          setState(() {});
        },
        child: ListView(
          children: [
            // Overview card with totals
            _buildOverviewCard(),
            const SizedBox(height: 16),

            // Top songs section
            _buildTopSongsSection(),
          ],
        ),
      ),
    );
  }

  /// Build the overview card showing total stats
  Widget _buildOverviewCard() {
    final stats = _statsService.getTotalStats();
    final avgDaily = _statsService.getAverageDailyTime();

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

              // Stats grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    label: 'Songs Played',
                    value: stats.totalSongsPlayed.toString(),
                  ),
                  _buildStatItem(
                    label: 'Total Time',
                    value: _formatDuration(stats.totalTimeStreamed),
                  ),
                  _buildStatItem(
                    label: 'Daily Avg',
                    value: _formatDuration(avgDaily),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a single stat item in the grid
  Widget _buildStatItem({required String label, required String value}) {
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
      ],
    );
  }

  /// Build the top songs section
  Widget _buildTopSongsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No stats yet. Start listening to see your top songs!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              );
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

  /// Build a single top song item
  Widget _buildTopSongItem(SongStats stat, int rank) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _getRankColor(rank),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

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

  /// Get color for rank badge
  Color _getRankColor(int rank) {
    if (rank == 1) return Colors.amber[700]!; // Gold
    if (rank == 2) return Colors.grey[400]!; // Silver
    if (rank == 3) return Colors.orange[700]!; // Bronze
    return Colors.blue;
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Statistics reset')),
                );
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
