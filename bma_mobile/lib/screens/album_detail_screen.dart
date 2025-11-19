import 'package:flutter/material.dart';
import '../models/api_models.dart';
import '../services/api/connection_service.dart';
import '../widgets/album/album_header.dart';
import '../widgets/album/track_list.dart';

/// Album detail screen with track listing and album actions
class AlbumDetailScreen extends StatefulWidget {
  final AlbumModel album;

  const AlbumDetailScreen({
    super.key,
    required this.album,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final ConnectionService _connectionService = ConnectionService();

  AlbumDetailResponse? _albumDetail;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAlbumDetail();
  }

  /// Load album detail with songs from server
  Future<void> _loadAlbumDetail() async {
    if (_connectionService.apiClient == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Not connected to server';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      print('[AlbumDetailScreen] ========== DEBUGGING ALBUM DETAIL ==========');
      print('[AlbumDetailScreen] Fetching album detail for ID: ${widget.album.id}');
      print('[AlbumDetailScreen] Album from library coverArt: ${widget.album.coverArt}');

      final detail = await _connectionService.apiClient!.getAlbumDetail(widget.album.id);

      print('[AlbumDetailScreen] Album detail loaded: ${detail.songs.length} tracks');
      print('[AlbumDetailScreen] Album detail coverArt: ${detail.coverArt}');
      print('[AlbumDetailScreen] Album detail year: ${detail.year}');
      print('[AlbumDetailScreen] ========================================');

      setState(() {
        _albumDetail = detail;
        _isLoading = false;
      });
    } catch (e) {
      print('[AlbumDetailScreen] ERROR loading album detail: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load album: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  /// Build the main content
  Widget _buildContent() {
    if (_albumDetail == null) {
      return const Center(child: Text('No album data'));
    }

    return CustomScrollView(
      slivers: [
        // Flexible header with artwork
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          flexibleSpace: AlbumArtworkHeader(
            coverArt: _albumDetail?.coverArt ?? widget.album.coverArt,
            albumTitle: widget.album.title,
          ),
        ),

        // Album info section
        SliverToBoxAdapter(
          child: _buildAlbumInfo(),
        ),

        // Action buttons
        SliverToBoxAdapter(
          child: _buildActionButtons(),
        ),

        // Track listing
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = _albumDetail!.songs[index];
              return TrackListItem(
                track: track,
                onTap: () => _playTrack(track, index),
                isCurrentTrack: false, // TODO: Connect to playback state
              );
            },
            childCount: _albumDetail!.songs.length,
          ),
        ),
      ],
    );
  }

  /// Build album information section
  Widget _buildAlbumInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album title (large)
          Text(
            widget.album.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Artist name
          Text(
            widget.album.artist,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),

          // Metadata row
          Row(
            children: [
              // Year (if available)
              if (_albumDetail?.year != null) ...[
                Text(
                  _albumDetail!.year!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 8),
                Text('•', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(width: 8),
              ],

              // Number of songs
              Text(
                '${widget.album.songCount} ${widget.album.songCount == 1 ? 'song' : 'songs'}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 8),
              Text('•', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(width: 8),

              // Total duration
              Text(
                _formatDuration(widget.album.duration),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build action buttons row
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // Primary actions row
          Row(
            children: [
              // Play All (primary action)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _playAll,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play All'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Shuffle
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shuffleAll,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Secondary actions row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addToQueue,
                  icon: const Icon(Icons.queue_music, size: 18),
                  label: const Text('Add to Queue'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addToPlaylist,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Add to Playlist'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAlbumDetail,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTION HANDLERS
  // ============================================================================

  void _playAll() {
    // TODO: Integrate with playback queue from Phase 6
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playing all tracks')),
    );
  }

  void _shuffleAll() {
    // TODO: Integrate with shuffle service from Phase 6
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shuffling album')),
    );
  }

  void _addToQueue() {
    // TODO: Integrate with playback queue from Phase 6
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added album to queue')),
    );
  }

  void _addToPlaylist() {
    // TODO: Implement in Task 7.5
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add to playlist - coming in Task 7.5')),
    );
  }

  void _playTrack(SongModel track, int index) {
    // TODO: Integrate with playback system from Phase 6
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing "${track.title}"')),
    );
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  /// Format duration in seconds to human-readable format
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '$hours hr $minutes min';
    } else {
      return '$minutes min';
    }
  }
}
