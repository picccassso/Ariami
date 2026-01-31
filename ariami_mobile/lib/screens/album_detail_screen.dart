import 'package:flutter/material.dart';
import '../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../models/api_models.dart';
import '../models/song.dart';
import '../models/download_task.dart';
import '../services/api/connection_service.dart';
import '../services/playback_manager.dart';
import '../services/playlist_service.dart';
import '../services/offline/offline_playback_service.dart';
import '../services/download/download_manager.dart';
import '../services/cache/cache_manager.dart';
import '../services/quality/quality_settings_service.dart';
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
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();

  AlbumDetailResponse? _albumDetail;
  bool _isLoading = true;
  String? _errorMessage;
  Set<String> _downloadedSongIds = {};
  Set<String> _cachedSongIds = {};

  @override
  void initState() {
    super.initState();
    _loadAlbumDetail();
    _loadDownloadedSongs();
    _loadCachedSongs();
  }

  /// Load downloaded song IDs
  void _loadDownloadedSongs() {
    final queue = _downloadManager.queue;
    final downloadedIds = <String>{};

    for (final task in queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedIds.add(task.songId);
      }
    }

    setState(() {
      _downloadedSongIds = downloadedIds;
    });
  }

  /// Load cached song IDs for this album
  Future<void> _loadCachedSongs() async {
    if (_albumDetail == null) return;

    final cachedIds = <String>{};
    for (final song in _albumDetail!.songs) {
      final isCached = await _cacheManager.isSongCached(song.id);
      if (isCached) {
        cachedIds.add(song.id);
      }
    }

    if (mounted) {
      setState(() {
        _cachedSongIds = cachedIds;
      });
    }
  }

  /// Load album detail with songs from server (or from downloads if offline)
  Future<void> _loadAlbumDetail() async {
    // If offline mode is enabled, build from downloads
    if (_offlineService.isOfflineModeEnabled) {
      print('[AlbumDetailScreen] Offline mode - building from downloads');
      _buildAlbumDetailFromDownloads();
      return;
    }
    
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

      // Load cached songs after album detail loads
      await _loadCachedSongs();
    } catch (e) {
      print('[AlbumDetailScreen] ERROR loading album detail: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load album: $e';
      });
    }
  }

  /// Build album detail from downloaded songs when offline
  void _buildAlbumDetailFromDownloads() {
    final queue = _downloadManager.queue;
    final downloadTasks = queue
        .where((t) =>
            t.status == DownloadStatus.completed &&
            t.albumId == widget.album.id)
        .toList();

    // Get album metadata from first task (if available)
    final firstTask = downloadTasks.isNotEmpty ? downloadTasks.first : null;
    final albumName = firstTask?.albumName ?? widget.album.title;
    final albumArtist = firstTask?.albumArtist ?? widget.album.artist;

    // Build song models from download tasks
    final albumSongs = downloadTasks
        .map((t) => SongModel(
            id: t.songId,
            title: t.title,
            artist: t.artist,
            albumId: t.albumId,
            duration: t.duration,
            trackNumber: t.trackNumber,
          ))
        .toList();

    // Sort by track number
    albumSongs.sort((a, b) => (a.trackNumber ?? 999).compareTo(b.trackNumber ?? 999));

    print('[AlbumDetailScreen] Built ${albumSongs.length} songs from downloads');
    print('[AlbumDetailScreen] Album: $albumName by $albumArtist');

    setState(() {
      _albumDetail = AlbumDetailResponse(
        id: widget.album.id,
        title: albumName,  // Use from download task if available
        artist: albumArtist,  // Use albumArtist from download task
        songs: albumSongs,
        coverArt: null, // No cover art available offline
        year: null,
      );
      _isLoading = false;
    });
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
          actions: [
            IconButton(
              icon: Icon(
                _albumDetail != null && _albumDetail!.songs.every((s) => _downloadedSongIds.contains(s.id))
                    ? Icons.download_done_rounded
                    : Icons.download_for_offline_rounded,
                color: _albumDetail != null && _albumDetail!.songs.every((s) => _downloadedSongIds.contains(s.id))
                    ? Colors.green
                    : Colors.white,
              ),
              onPressed: _albumDetail != null && !_albumDetail!.songs.every((s) => _downloadedSongIds.contains(s.id))
                  ? _downloadAlbum
                  : null,
              tooltip: 'Download Album',
            ),
          ],
          flexibleSpace: AlbumArtworkHeader(
            coverArt: _albumDetail?.coverArt ?? widget.album.coverArt,
            albumTitle: widget.album.title,
            albumId: widget.album.id,
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
              final isDownloaded = _downloadedSongIds.contains(track.id);
              final isCached = _cachedSongIds.contains(track.id);
              final isOffline = _offlineService.isOffline;
              final isAvailable = !isOffline || isDownloaded || isCached;

              return TrackListItem(
                track: track,
                onTap: isAvailable ? () => _playTrack(track, index) : null,
                isCurrentTrack: false, // TODO: Connect to playback state
                isDownloaded: isDownloaded,
                isCached: isCached,
                isAvailable: isAvailable,
                albumName: widget.album.title,
                albumArtist: widget.album.artist,
              );
            },
            childCount: _albumDetail!.songs.length,
          ),
        ),

        // Bottom padding for mini player + download bar + nav bar
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: getMiniPlayerAwareBottomPadding(),
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

  /// Action buttons (Play, Shuffle, etc.)
  Widget _buildActionButtons() {
    final songs = _albumDetail?.songs ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // Primary actions row (Play/Shuffle)
          Row(
            children: [
              // Play Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: songs.isEmpty ? null : _playAll,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'Play',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Shuffle Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: songs.isEmpty ? null : _shuffleAll,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 22),
                  label: const Text(
                    'Shuffle',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Secondary actions row (Queue/Playlist)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addToQueue,
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  icon: const Icon(Icons.queue_music_rounded, size: 20),
                  label: const Text('Queue'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addToPlaylist,
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  label: const Text('Playlist'),
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

  /// Download entire album
  void _downloadAlbum() {
    if (_albumDetail == null) return;
    
    // Check connection
    if (_connectionService.apiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to server')),
      );
      return;
    }

    final songsToDownload = _albumDetail!.songs
        .where((s) => !_downloadedSongIds.contains(s.id))
        .toList();

    if (songsToDownload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All songs already downloaded')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Starting download of ${songsToDownload.length} songs...')),
    );

    // Queue downloads
    // Note: In a real implementation, we might want to batch this or use a dedicated album download method
    // For now, we queue individual songs
    // We already have _handleDownload logic in SongListItem, but we can access DownloadManager directly
    
    final qualityService = QualitySettingsService();

    for (final song in songsToDownload) {
      final baseDownloadUrl = _connectionService.apiClient!.getDownloadUrl(song.id);
      final downloadUrl = qualityService.getDownloadUrlWithQuality(baseDownloadUrl);

      _downloadManager.downloadSong(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        albumId: song.albumId,
        albumName: widget.album.title,
        albumArtist: widget.album.artist,
        albumArt: '', // Manager handles this or fetches it
        downloadUrl: downloadUrl,
        duration: song.duration,
        trackNumber: song.trackNumber,
        totalBytes: 0,
      );
    }
  }

  void _playAll() async {
    if (_albumDetail == null) return;

    print('[AlbumDetailScreen] Playing all tracks in album...');

    // Filter songs for offline mode (include both downloaded and cached)
    final isOffline = _offlineService.isOffline;
    final songsToPlay = isOffline
        ? _albumDetail!.songs.where((s) => 
            _downloadedSongIds.contains(s.id) || _cachedSongIds.contains(s.id)).toList()
        : _albumDetail!.songs;

    if (songsToPlay.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No offline songs available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Convert songs
    final allSongs = songsToPlay.map((songModel) => Song(
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
      await _playbackManager.playSongs(allSongs);
    } catch (e) {
      print('[AlbumDetailScreen] Error playing all: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _shuffleAll() async {
    if (_albumDetail == null) return;

    print('[AlbumDetailScreen] Shuffling all tracks in album...');

    // Filter songs for offline mode (include both downloaded and cached)
    final isOffline = _offlineService.isOffline;
    final songsToPlay = isOffline
        ? _albumDetail!.songs.where((s) => 
            _downloadedSongIds.contains(s.id) || _cachedSongIds.contains(s.id)).toList()
        : _albumDetail!.songs;

    if (songsToPlay.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No offline songs available'),
            backgroundColor: Color(0xFF141414),
          ),
        );
      }
      return;
    }

    // Convert songs
    final allSongs = songsToPlay.map((songModel) => Song(
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
      await _playbackManager.playShuffled(allSongs);
    } catch (e) {
      print('[AlbumDetailScreen] Error shuffling: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
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

    final isOffline = _offlineService.isOffline;

    // Get songs to add to queue - filter to downloaded only when offline
    List<SongModel> songsForQueue;
    int startIndex;

    if (isOffline) {
      // In offline mode, only add downloaded songs to queue
      songsForQueue = _albumDetail!.songs
          .where((s) => _downloadedSongIds.contains(s.id))
          .toList();
      // Find the index of the clicked track in the filtered list
      startIndex = songsForQueue.indexWhere((s) => s.id == track.id);
      if (startIndex == -1) startIndex = 0;
      print('[AlbumDetailScreen] Offline mode: ${songsForQueue.length} downloaded songs in queue');
    } else {
      // Online mode - add all songs
      songsForQueue = _albumDetail!.songs;
      startIndex = index;
    }

    // Convert to Song models for queue
    // Use _albumDetail if available (has updated metadata from downloads), otherwise use widget.album
    final albumTitle = _albumDetail?.title ?? widget.album.title;
    final albumArtistName = _albumDetail?.artist ?? widget.album.artist;

    final allSongs = songsForQueue.map((songModel) => Song(
      id: songModel.id,
      title: songModel.title,
      artist: songModel.artist,  // Song artist (may include features)
      album: albumTitle,  // Album title
      albumId: widget.album.id,
      albumArtist: albumArtistName,  // Album artist (main artist)
      duration: Duration(seconds: songModel.duration),
      filePath: songModel.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: songModel.trackNumber,
    )).toList();

    print('[AlbumDetailScreen] Converted ${allSongs.length} songs for queue');
    print('[AlbumDetailScreen] Calling PlaybackManager.playSongs() starting at index $startIndex...');

    try {
      // Play songs starting from clicked track
      await _playbackManager.playSongs(allSongs, startIndex: startIndex);
      print('[AlbumDetailScreen] ✅ Playback started successfully!');
    } catch (e, stackTrace) {
      print('[AlbumDetailScreen] ❌ ERROR: $e');
      print('[AlbumDetailScreen] Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play: $e'),
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
          title: song.title,
          artist: song.artist,
          duration: song.duration,
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
                        padding: EdgeInsets.only(
                          bottom: getMiniPlayerAwareBottomPadding(),
                        ),
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
