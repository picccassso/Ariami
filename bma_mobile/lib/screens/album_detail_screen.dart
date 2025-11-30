import 'package:flutter/material.dart';
import '../models/api_models.dart';
import '../models/song.dart';
import '../services/api/connection_service.dart';
import '../services/playback_manager.dart';
import '../services/playlist_service.dart';
import '../widgets/album/album_header.dart';
import '../widgets/album/track_list.dart';
import 'playlist/create_playlist_screen.dart';

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
  final PlaybackManager _playbackManager = PlaybackManager();

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
    // Calculate total duration from loaded songs
    final totalDuration = _albumDetail != null
        ? _albumDetail!.songs.fold<int>(0, (sum, song) => sum + song.duration)
        : widget.album.duration;
    final songCount = _albumDetail?.songs.length ?? widget.album.songCount;

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
                '$songCount ${songCount == 1 ? 'song' : 'songs'}',
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
                _formatDuration(totalDuration),
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
                child: FilledButton(
                  onPressed: _playAll,
                  child: const Icon(Icons.play_arrow),
                ),
              ),
              const SizedBox(width: 12),

              // Shuffle
              Expanded(
                child: OutlinedButton(
                  onPressed: _shuffleAll,
                  child: const Icon(Icons.shuffle),
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

  /// Attempt to reconnect and reload album detail
  Future<void> _retryConnection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // First try to restore connection
    final restored = await _connectionService.tryRestoreConnection();

    if (restored) {
      // Connection restored - load album detail
      await _loadAlbumDetail();
    } else {
      // Still can't connect - navigate to reconnect screen
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/reconnect',
          (route) => false,
        );
      }
    }
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
            onPressed: _retryConnection,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTION HANDLERS
  // ============================================================================

  void _playAll() async {
    if (_albumDetail == null) return;

    print('[AlbumDetailScreen] Playing all tracks in album...');

    // Convert all songs
    final allSongs = _albumDetail!.songs.map((songModel) => Song(
      id: songModel.id,
      title: songModel.title,
      artist: songModel.artist,
      album: widget.album.title,
      albumId: widget.album.id, // Add albumId for artwork
      duration: Duration(seconds: songModel.duration),
      filePath: songModel.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: songModel.trackNumber,
    )).toList();

    try {
      await _playbackManager.playSongs(allSongs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Playing all tracks'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[AlbumDetailScreen] Error playing all: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _shuffleAll() async {
    if (_albumDetail == null) return;

    print('[AlbumDetailScreen] Shuffling all tracks in album...');

    // Convert all songs
    final allSongs = _albumDetail!.songs.map((songModel) => Song(
      id: songModel.id,
      title: songModel.title,
      artist: songModel.artist,
      album: widget.album.title,
      albumId: widget.album.id, // Add albumId for artwork
      duration: Duration(seconds: songModel.duration),
      filePath: songModel.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: songModel.trackNumber,
    )).toList();

    try {
      await _playbackManager.playShuffled(allSongs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Shuffling album'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[AlbumDetailScreen] Error shuffling: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addToQueue() {
    if (_albumDetail == null || _albumDetail!.songs.isEmpty) {
      return;
    }

    // Convert all album songs to Song objects
    final allSongs = _albumDetail!.songs.map((songModel) => Song(
      id: songModel.id,
      title: songModel.title,
      artist: songModel.artist,
      album: widget.album.title,
      albumId: widget.album.id,
      duration: Duration(seconds: songModel.duration),
      filePath: songModel.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: songModel.trackNumber,
    )).toList();

    try {
      _playbackManager.addAllToQueue(allSongs);
    } catch (e) {
      print('[AlbumDetailScreen] Error adding to queue: $e');
    }
  }

  void _addToPlaylist() async {
    if (_albumDetail == null || _albumDetail!.songs.isEmpty) {
      return;
    }

    // Show bottom sheet to select playlist
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _AlbumPlaylistPicker(
        albumSongs: _albumDetail!.songs,
        albumId: widget.album.id,
        albumTitle: widget.album.title,
      ),
    );
  }

  void _playTrack(SongModel track, int index) async {
    print('==========================================================');
    print('[AlbumDetailScreen] _playTrack called for: ${track.title}');
    print('[AlbumDetailScreen] Track index: $index');
    print('==========================================================');

    // Convert all album songs to Song models for queue
    final allSongs = _albumDetail!.songs.map((songModel) => Song(
      id: songModel.id,
      title: songModel.title,
      artist: songModel.artist,
      album: widget.album.title,
      albumId: widget.album.id, // Add albumId for artwork
      duration: Duration(seconds: songModel.duration),
      filePath: songModel.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: songModel.trackNumber,
    )).toList();

    print('[AlbumDetailScreen] Converted ${allSongs.length} songs for queue');
    print('[AlbumDetailScreen] Calling PlaybackManager.playSongs() starting at index $index...');

    try {
      // Play all songs starting from clicked track
      await _playbackManager.playSongs(allSongs, startIndex: index);
      print('[AlbumDetailScreen] ✅ Playback started successfully!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Playing "${track.title}"'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('[AlbumDetailScreen] ❌ ERROR: $e');
      print('[AlbumDetailScreen] Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to play: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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

/// Bottom sheet for adding album songs to a playlist
class _AlbumPlaylistPicker extends StatefulWidget {
  final List<SongModel> albumSongs;
  final String albumId;
  final String albumTitle;

  const _AlbumPlaylistPicker({
    required this.albumSongs,
    required this.albumId,
    required this.albumTitle,
  });

  @override
  State<_AlbumPlaylistPicker> createState() => _AlbumPlaylistPickerState();
}

class _AlbumPlaylistPickerState extends State<_AlbumPlaylistPicker> {
  final PlaylistService _playlistService = PlaylistService();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _playlistService.loadPlaylists();
    _playlistService.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    super.dispose();
  }

  void _onPlaylistsChanged() {
    setState(() {});
  }

  Future<void> _createNewPlaylist() async {
    final playlist = await CreatePlaylistScreen.show(context);
    if (playlist != null && mounted) {
      await _addAlbumToPlaylist(playlist);
    }
  }

  Future<void> _addAlbumToPlaylist(PlaylistModel playlist) async {
    setState(() => _isAdding = true);

    int addedCount = 0;
    for (final song in widget.albumSongs) {
      if (!playlist.songIds.contains(song.id)) {
        await _playlistService.addSongToPlaylist(
          playlistId: playlist.id,
          songId: song.id,
          albumId: song.albumId,
        );
        addedCount++;
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $addedCount ${addedCount == 1 ? 'song' : 'songs'} to "${playlist.name}"'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlistService.playlists;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Add Album to Playlist',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Album info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              '${widget.albumSongs.length} songs from "${widget.albumTitle}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),

          const SizedBox(height: 8),

          // Create new playlist option
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.add, color: Colors.grey),
            ),
            title: const Text('Create New Playlist'),
            onTap: _isAdding ? null : _createNewPlaylist,
          ),

          const Divider(),

          // Playlists list
          Expanded(
            child: _isAdding
                ? const Center(child: CircularProgressIndicator())
                : playlists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue_music, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'No playlists yet',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          final songsAlreadyInPlaylist = widget.albumSongs
                              .where((song) => playlist.songIds.contains(song.id))
                              .length;
                          final allSongsInPlaylist =
                              songsAlreadyInPlaylist == widget.albumSongs.length;

                          return ListTile(
                            leading: _buildPlaylistIcon(playlist),
                            title: Text(playlist.name),
                            subtitle: Text(
                              allSongsInPlaylist
                                  ? 'All songs already in playlist'
                                  : songsAlreadyInPlaylist > 0
                                      ? '$songsAlreadyInPlaylist/${widget.albumSongs.length} songs already added'
                                      : '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
                            ),
                            trailing: allSongsInPlaylist
                                ? const Icon(Icons.check, color: Colors.green)
                                : const Icon(Icons.add),
                            onTap: () => _addAlbumToPlaylist(playlist),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistIcon(PlaylistModel playlist) {
    // Special styling for Liked Songs
    if (playlist.id == PlaylistService.likedSongsId) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.pink[400]!, Colors.red[700]!],
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.favorite, color: Colors.white, size: 24),
      );
    }

    // Regular playlist
    final colorIndex = playlist.name.hashCode % 5;
    final colors = [
      Colors.purple[400]!,
      Colors.blue[400]!,
      Colors.green[400]!,
      Colors.orange[400]!,
      Colors.pink[400]!,
    ];

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors[colorIndex],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.queue_music, color: Colors.white, size: 24),
    );
  }
}
