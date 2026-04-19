import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../models/api_models.dart';
import '../models/song.dart';
import '../models/download_task.dart';
import '../models/websocket_models.dart';
import '../services/api/connection_service.dart';
import '../services/playback_manager.dart';
import '../services/offline/offline_playback_service.dart';
import '../services/download/download_manager.dart';
import '../services/cache/cache_manager.dart';
import '../screens/main/library/library_controller.dart';
import '../widgets/album/album_action_buttons.dart';
import '../widgets/album/album_header.dart';
import '../widgets/album/album_info_section.dart';
import '../widgets/album/album_playlist_picker_sheet.dart';
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
  final PlaybackManager _playbackManager = PlaybackManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();
  final LibraryController _libraryController = LibraryController();

  AlbumDetailResponse? _albumDetail;
  bool _isLoading = true;
  String? _errorMessage;
  Set<String> _downloadedSongIds = {};
  Set<String> _cachedSongIds = {};
  StreamSubscription<WsMessage>? _webSocketSubscription;

  @override
  void initState() {
    super.initState();
    _loadAlbumDetail();
    _loadDownloadedSongs();
    _loadCachedSongs();
    _webSocketSubscription = _connectionService.webSocketMessages.listen(
      _handleLibrarySyncMessage,
    );
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    super.dispose();
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

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final detail = await _connectionService.libraryReadFacade
          .getAlbumDetail(widget.album.id);
      if (detail == null) {
        throw StateError('Album not found');
      }

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
    albumSongs
        .sort((a, b) => (a.trackNumber ?? 999).compareTo(b.trackNumber ?? 999));

    print(
        '[AlbumDetailScreen] Built ${albumSongs.length} songs from downloads');
    print('[AlbumDetailScreen] Album: $albumName by $albumArtist');

    setState(() {
      _albumDetail = AlbumDetailResponse(
        id: widget.album.id,
        title: albumName, // Use from download task if available
        artist: albumArtist, // Use albumArtist from download task
        songs: albumSongs,
        coverArt: null, // No cover art available offline
        year: null,
      );
      _isLoading = false;
    });
  }

  void _handleLibrarySyncMessage(WsMessage message) {
    if (message.type != WsMessageType.syncTokenAdvanced &&
        message.type != WsMessageType.libraryUpdated) {
      return;
    }
    if (!mounted || _isLoading || _offlineService.isOfflineModeEnabled) {
      return;
    }
    unawaited(_loadAlbumDetail());
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

    // Square flexible region (matches library cards) to avoid letterboxing.
    final expandedArtHeight =
        MediaQuery.sizeOf(context).width.clamp(200.0, 600.0);

    return CustomScrollView(
      slivers: [
        // Flexible header with artwork
        SliverAppBar(
          expandedHeight: expandedArtHeight,
          pinned: true,
          actions: [
            IconButton(
              icon: Icon(
                _albumDetail != null &&
                        _albumDetail!.songs
                            .every((s) => _downloadedSongIds.contains(s.id))
                    ? Icons.download_done_rounded
                    : Icons.download_for_offline_rounded,
                color: _albumDetail != null &&
                        _albumDetail!.songs
                            .every((s) => _downloadedSongIds.contains(s.id))
                    ? Colors.green
                    : Colors.white,
              ),
              onPressed: _albumDetail != null &&
                      !_albumDetail!.songs
                          .every((s) => _downloadedSongIds.contains(s.id))
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
          child: AlbumInfoSection(
            albumTitle: widget.album.title,
            albumArtist: widget.album.artist,
            year: _albumDetail?.year,
            songCount: _albumDetail?.songs.length ?? widget.album.songCount,
            totalDurationSeconds: _albumDetail != null
                ? _albumDetail!.songs
                    .fold<int>(0, (sum, song) => sum + song.duration)
                : widget.album.duration,
          ),
        ),

        // Action buttons
        SliverToBoxAdapter(
          child: AlbumActionButtons(
            isAlbumFullyDownloaded: _albumDetail != null &&
                _albumDetail!.songs
                    .every((song) => _downloadedSongIds.contains(song.id)),
            hasSongs: (_albumDetail?.songs ?? []).isNotEmpty,
            onDownloadAlbum: _albumDetail != null &&
                    !_albumDetail!.songs
                        .every((song) => _downloadedSongIds.contains(song.id))
                ? _downloadAlbum
                : null,
            onAddToPlaylist: _addToPlaylist,
            onAddToQueue: _addToQueue,
            onShuffleAll: _shuffleAll,
            onPlayAll: _playAll,
          ),
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
            bottom: getMiniPlayerAwareBottomPadding(context),
          ),
        ),
      ],
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
      SnackBar(
          content:
              Text('Starting download of ${songsToDownload.length} songs...')),
    );

    // Queue downloads
    // Note: In a real implementation, we might want to batch this or use a dedicated album download method
    // For now, we queue individual songs
    // We already have _handleDownload logic in SongListItem, but we can access DownloadManager directly

    for (final song in songsToDownload) {
      _downloadManager.downloadSong(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        albumId: song.albumId,
        albumName: widget.album.title,
        albumArtist: widget.album.artist,
        albumArt: '', // Manager handles this or fetches it
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
        ? _albumDetail!.songs
            .where((s) =>
                _downloadedSongIds.contains(s.id) ||
                _cachedSongIds.contains(s.id))
            .toList()
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
    final allSongs = songsToPlay
        .map((songModel) => Song(
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
            ))
        .toList();

    try {
      unawaited(_libraryController.markAlbumPlayed(widget.album.id));
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
        ? _albumDetail!.songs
            .where((s) =>
                _downloadedSongIds.contains(s.id) ||
                _cachedSongIds.contains(s.id))
            .toList()
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
    final allSongs = songsToPlay
        .map((songModel) => Song(
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
            ))
        .toList();

    try {
      unawaited(_libraryController.markAlbumPlayed(widget.album.id));
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
    final allSongs = _albumDetail!.songs
        .map((songModel) => Song(
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
            ))
        .toList();

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
      builder: (context) => AlbumPlaylistPickerSheet(
        albumSongs: _albumDetail!.songs,
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
      print(
          '[AlbumDetailScreen] Offline mode: ${songsForQueue.length} downloaded songs in queue');
    } else {
      // Online mode - add all songs
      songsForQueue = _albumDetail!.songs;
      startIndex = index;
    }

    // Convert to Song models for queue
    // Use _albumDetail if available (has updated metadata from downloads), otherwise use widget.album
    final albumTitle = _albumDetail?.title ?? widget.album.title;
    final albumArtistName = _albumDetail?.artist ?? widget.album.artist;

    final allSongs = songsForQueue
        .map((songModel) => Song(
              id: songModel.id,
              title: songModel.title,
              artist: songModel.artist, // Song artist (may include features)
              album: albumTitle, // Album title
              albumId: widget.album.id,
              albumArtist: albumArtistName, // Album artist (main artist)
              duration: Duration(seconds: songModel.duration),
              filePath: songModel.id,
              fileSize: 0,
              modifiedTime: DateTime.now(),
              trackNumber: songModel.trackNumber,
            ))
        .toList();

    print('[AlbumDetailScreen] Converted ${allSongs.length} songs for queue');
    print(
        '[AlbumDetailScreen] Calling PlaybackManager.playSongs() starting at index $startIndex...');

    try {
      // Play songs starting from clicked track
      unawaited(_libraryController.markAlbumPlayed(widget.album.id));
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
}
