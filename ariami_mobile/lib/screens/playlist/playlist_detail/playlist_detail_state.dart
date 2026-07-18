part of '../playlist_detail_screen.dart';

/// Owns the playlist screen lifecycle, subscriptions, and refresh state.
///
/// Song metadata resolution is implemented by [_PlaylistSongResolutionState]
/// so the loading state machine stays separate from metadata fallbacks.
abstract class _PlaylistDetailState extends State<PlaylistDetailScreen> {
  final PlaylistService _playlistService = PlaylistService();
  final ConnectionService _connectionService = ConnectionService();
  final PlaybackManager _playbackManager = PlaybackManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final OfflineCopyService _offlineCopyService = OfflineCopyService();
  final DownloadManager _downloadManager = DownloadManager();
  final LibraryRepository _libraryRepository = LibraryRepository();
  final LibraryController _libraryController = LibraryController();

  PlaylistModel? _playlist;
  List<SongModel> _songs = [];
  bool _isLoading = true;
  bool _isSongsLoading = false;
  String? _errorMessage;
  bool _isReorderMode = false;
  Set<String> _downloadedSongIds = {};
  StreamSubscription<WsMessage>? _webSocketSubscription;
  bool _pendingSyncRefresh = false;
  late final DownloadStateWatcher _downloadStateWatcher;

  // Map of albumId to album info (name, artist) for stats tracking
  final Map<String, ({String name, String artist})> _albumInfoMap = {};

  Future<List<SongModel>> _resolveSongs(List<String> songIds);

  List<SongModel> _buildSongsFromStoredMetadata(
    PlaylistModel playlist, {
    Map<String, SongModel> preferredSongsById = const <String, SongModel>{},
  });

  bool _needsLibrarySongMetadata(List<SongModel> songs);

  @override
  void initState() {
    super.initState();
    _downloadStateWatcher = DownloadStateWatcher(
      onChanged: _applyDownloadedSongIds,
    );
    _downloadStateWatcher.start();
    _loadDownloadedSongs();
    unawaited(_loadPlaylist().then((_) => _showOfflineCopyNoticeIfNeeded()));
    _playlistService.addListener(_onPlaylistsChanged);
    _webSocketSubscription = _connectionService.webSocketMessages.listen(
      _handleLibrarySyncMessage,
    );
  }

  @override
  void dispose() {
    _downloadStateWatcher.dispose();
    _playlistService.removeListener(_onPlaylistsChanged);
    _webSocketSubscription?.cancel();
    super.dispose();
  }

  void _onPlaylistsChanged() {
    _refreshPlaylistData();
  }

  void _handleLibrarySyncMessage(WsMessage message) {
    if (message.type != WsMessageType.syncTokenAdvanced &&
        message.type != WsMessageType.libraryUpdated) {
      return;
    }
    if (!mounted || _playlist == null) {
      _pendingSyncRefresh = true;
      return;
    }
    if (_isLoading || _isSongsLoading) {
      _pendingSyncRefresh = true;
      return;
    }
    unawaited(_reloadSongsFromLibrarySync());
  }

  Future<void> _reloadSongsFromLibrarySync() async {
    final playlist = _playlist;
    if (playlist == null) return;

    final songs = await _resolveSongs(playlist.songIds);
    if (!mounted) return;

    setState(() {
      _songs = songs;
    });
    _pendingSyncRefresh = false;
  }

  void _applyDownloadedSongIds(Set<String> downloadedIds) {
    if (!mounted) return;
    if (_downloadedSongIds.length == downloadedIds.length &&
        _downloadedSongIds.containsAll(downloadedIds)) {
      return;
    }
    setState(() {
      _downloadedSongIds = downloadedIds;
    });
  }

  /// Load downloaded song IDs
  void _loadDownloadedSongs() {
    _applyDownloadedSongIds(
      DownloadStateWatcher.completedSongIds(_downloadManager.queue),
    );
  }

  /// Refresh playlist data without showing loading indicator
  Future<void> _refreshPlaylistData() async {
    final playlist = _playlistService.getPlaylist(widget.playlistId);

    if (playlist == null) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final currentSongIds = _songs.map((s) => s.id).toSet();
    final newSongIds = playlist.songIds.toSet();
    final fallbackSongs = _buildSongsFromStoredMetadata(
      playlist,
      preferredSongsById: {for (final song in _songs) song.id: song},
    );

    if (currentSongIds.length != newSongIds.length ||
        !currentSongIds.containsAll(newSongIds)) {
      final songs = await _resolveSongs(playlist.songIds);
      if (mounted) {
        setState(() {
          _playlist = playlist;
          _songs = songs;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _playlist = playlist;
          _songs = fallbackSongs;
        });
      }
    }
  }

  /// Load playlist and resolve song IDs to full song data
  Future<void> _loadPlaylist() async {
    final cachedPlaylist = _playlistService.getPlaylist(widget.playlistId);

    if (cachedPlaylist != null) {
      final initialSongs = _buildSongsFromStoredMetadata(cachedPlaylist);
      final needsLibraryMetadata = _needsLibrarySongMetadata(initialSongs);
      setState(() {
        _playlist = cachedPlaylist;
        _songs = initialSongs;
        _isLoading = false;
        _isSongsLoading = needsLibraryMetadata;
      });

      if (!needsLibraryMetadata && _pendingSyncRefresh) {
        await _reloadSongsFromLibrarySync();
      }

      if (needsLibraryMetadata) {
        final songs = await _resolveSongs(cachedPlaylist.songIds);
        if (mounted) {
          setState(() {
            _songs = songs;
            _isSongsLoading = false;
          });
        }
        if (_pendingSyncRefresh) {
          await _reloadSongsFromLibrarySync();
        }
      }
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        await _playlistService.loadPlaylists();
        final playlist = _playlistService.getPlaylist(widget.playlistId);

        if (playlist == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Playlist not found';
          });
          return;
        }

        setState(() {
          _playlist = playlist;
          _songs = _buildSongsFromStoredMetadata(playlist);
          _isLoading = false;
          _isSongsLoading = _needsLibrarySongMetadata(_songs);
        });

        if (!_isSongsLoading && _pendingSyncRefresh) {
          await _reloadSongsFromLibrarySync();
        }

        if (_isSongsLoading) {
          final songs = await _resolveSongs(playlist.songIds);
          if (!mounted) return;

          setState(() {
            _songs = songs;
            _isSongsLoading = false;
          });
          if (_pendingSyncRefresh) {
            await _reloadSongsFromLibrarySync();
          }
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load playlist: $e';
        });
      }
    }
  }

  Future<void> _showOfflineCopyNoticeIfNeeded();
}
