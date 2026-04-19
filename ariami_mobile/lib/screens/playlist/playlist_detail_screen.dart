import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../models/api_models.dart';
import '../../models/download_task.dart';
import '../../models/websocket_models.dart';
import '../../services/api/connection_service.dart';
import '../../services/library/library_repository.dart';
import '../../services/playlist_service.dart';
import '../../services/playback_manager.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/download/download_manager.dart';
import 'add_to_playlist_screen.dart';
import '../main/library/library_controller.dart';
import 'utils/playlist_helpers.dart';
import 'widgets/widgets.dart';

/// Playlist detail screen with editable header, reorderable songs, and playback actions
class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PlaylistService _playlistService = PlaylistService();
  final ConnectionService _connectionService = ConnectionService();
  final PlaybackManager _playbackManager = PlaybackManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
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

  // Map of albumId to album info (name, artist) for stats tracking
  final Map<String, ({String name, String artist})> _albumInfoMap = {};

  @override
  void initState() {
    super.initState();
    _loadDownloadedSongs();
    _loadPlaylist();
    _playlistService.addListener(_onPlaylistsChanged);
    _webSocketSubscription = _connectionService.webSocketMessages.listen(
      _handleLibrarySyncMessage,
    );
  }

  @override
  void dispose() {
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

  /// Resolve song IDs to SongModel objects
  Future<List<SongModel>> _resolveSongs(List<String> songIds) async {
    if (songIds.isEmpty) {
      return [];
    }

    if (_offlineService.isOffline || _connectionService.apiClient == null) {
      return await _resolveSongsFromDownloads(songIds);
    }

    final songs = await _resolveSongsFromLocalMetadata(songIds);
    _fetchAlbumInfoInBackground();

    return songs;
  }

  /// Fetch album info from server in background
  void _fetchAlbumInfoInBackground() {
    unawaited(() async {
      try {
        final albums = await _connectionService.libraryReadFacade.getAlbums();

        for (final album in albums) {
          _albumInfoMap[album.id] = (name: album.title, artist: album.artist);
        }

        for (final task in _downloadManager.queue) {
          if (task.status == DownloadStatus.completed &&
              task.albumId != null &&
              task.albumName != null &&
              !_albumInfoMap.containsKey(task.albumId)) {
            _albumInfoMap[task.albumId!] = (
              name: task.albumName!,
              artist: task.albumArtist ?? task.artist,
            );
          }
        }

        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        print('[PlaylistDetailScreen] Background album info load failed: $e');
      }
    }());
  }

  Future<List<SongModel>> _loadLibrarySongsForMetadata() async {
    try {
      final localSongs = await _libraryRepository.getSongs();
      if (localSongs.isNotEmpty) {
        return localSongs;
      }
    } catch (e) {
      print(
          '[PlaylistDetailScreen] Local repository song metadata load failed: $e');
    }

    try {
      return await _connectionService.libraryReadFacade.getSongs();
    } catch (e) {
      print('[PlaylistDetailScreen] Facade song metadata load failed: $e');
      return const <SongModel>[];
    }
  }

  List<SongModel> _buildSongsFromStoredMetadata(
    PlaylistModel playlist, {
    Map<String, SongModel> preferredSongsById = const <String, SongModel>{},
  }) {
    final downloadedSongs = _buildDownloadedSongsMap();

    return playlist.songIds.map((id) {
      final downloadedSong = downloadedSongs[id];
      if (downloadedSong != null) {
        return downloadedSong;
      }

      final preferredSong = preferredSongsById[id];
      final cachedTitle = playlist.songTitles[id];
      final cachedArtist = playlist.songArtists[id];
      final cachedDuration = playlist.songDurations[id];

      return SongModel(
        id: id,
        title: (cachedTitle != null && cachedTitle.isNotEmpty)
            ? cachedTitle
            : (preferredSong?.title ?? 'Unknown Song'),
        artist: (cachedArtist != null && cachedArtist.isNotEmpty)
            ? cachedArtist
            : (preferredSong?.artist ?? 'Unknown Artist'),
        albumId: playlist.songAlbumIds[id] ?? preferredSong?.albumId,
        duration: (cachedDuration != null && cachedDuration > 0)
            ? cachedDuration
            : (preferredSong?.duration ?? 0),
        trackNumber: preferredSong?.trackNumber,
      );
    }).toList();
  }

  Map<String, SongModel> _buildDownloadedSongsMap() {
    final downloadedSongs = <String, SongModel>{};

    for (final task in _downloadManager.queue) {
      if (task.status != DownloadStatus.completed) {
        continue;
      }

      downloadedSongs[task.songId] = SongModel(
        id: task.songId,
        title: task.title,
        artist: task.artist,
        albumId: task.albumId,
        duration: task.duration,
        trackNumber: task.trackNumber,
      );

      if (task.albumId != null && task.albumName != null) {
        _albumInfoMap[task.albumId!] =
            (name: task.albumName!, artist: task.albumArtist ?? task.artist);
      }
    }

    return downloadedSongs;
  }

  bool _needsLibrarySongMetadata(List<SongModel> songs) {
    return songs.any(
      (song) =>
          song.duration <= 0 ||
          song.title.isEmpty ||
          song.title == 'Unknown Song' ||
          song.artist.isEmpty ||
          song.artist == 'Unknown Artist',
    );
  }

  /// Build SongModel objects from playlist's locally-stored metadata
  Future<List<SongModel>> _resolveSongsFromLocalMetadata(
      List<String> songIds) async {
    final playlist = _playlist;
    if (playlist == null) {
      return const <SongModel>[];
    }

    final provisionalSongs = _buildSongsFromStoredMetadata(playlist);
    if (!_needsLibrarySongMetadata(provisionalSongs)) {
      return provisionalSongs;
    }

    final librarySongs = await _loadLibrarySongsForMetadata();
    final provisionalSongsById = {
      for (final song in provisionalSongs) song.id: song,
    };
    final librarySongsById = {for (final song in librarySongs) song.id: song};

    return songIds.map((id) {
      final provisionalSong = provisionalSongsById[id];
      final librarySong = librarySongsById[id];

      if (provisionalSong == null) {
        return librarySong ??
            SongModel(
              id: id,
              title: 'Unknown Song',
              artist: 'Unknown Artist',
              duration: 0,
            );
      }

      if (librarySong == null) {
        return provisionalSong;
      }

      return SongModel(
        id: id,
        title: provisionalSong.title == 'Unknown Song'
            ? librarySong.title
            : provisionalSong.title,
        artist: provisionalSong.artist == 'Unknown Artist'
            ? librarySong.artist
            : provisionalSong.artist,
        albumId: provisionalSong.albumId ?? librarySong.albumId,
        duration: provisionalSong.duration > 0
            ? provisionalSong.duration
            : librarySong.duration,
        trackNumber: provisionalSong.trackNumber ?? librarySong.trackNumber,
      );
    }).toList();
  }

  /// Build SongModel objects from downloaded song metadata
  Future<List<SongModel>> _resolveSongsFromDownloads(
      List<String> songIds) async {
    final downloadedSongs = _buildDownloadedSongsMap();

    // Pre-fetch song durations from library to fill in missing values
    final librarySongs = await _loadLibrarySongsForMetadata();
    final libraryDurations = {for (var s in librarySongs) s.id: s.duration};

    return songIds.map((id) {
      if (downloadedSongs.containsKey(id)) {
        return downloadedSongs[id]!;
      } else {
        final albumId = _playlist?.songAlbumIds[id];
        final title = _playlist?.songTitles[id] ?? 'Unknown Song';
        final artist = _playlist?.songArtists[id] ?? 'Unknown Artist';
        var duration = _playlist?.songDurations[id] ?? 0;
        // Fallback to library duration if playlist duration is 0 or missing
        if (duration == 0 && libraryDurations.containsKey(id)) {
          duration = libraryDurations[id]!;
        }
        return SongModel(
          id: id,
          title: title,
          artist: artist,
          albumId: albumId,
          duration: duration,
          trackNumber: null,
        );
      }
    }).toList();
  }

  /// Play all songs from playlist
  Future<void> _playAll() async {
    if (_songs.isEmpty) return;

    final isOffline = _offlineService.isOffline;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    if (songsToPlay.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No downloaded songs available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final songs =
        songsToPlay.map((s) => songModelToSong(s, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playSongs(songs, startIndex: 0);
  }

  /// Shuffle play all songs
  Future<void> _shuffleAll() async {
    if (_songs.isEmpty) return;

    final isOffline = _offlineService.isOffline;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    if (songsToPlay.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No downloaded songs available'),
            backgroundColor: Color(0xFF141414),
          ),
        );
      }
      return;
    }

    final songs =
        songsToPlay.map((s) => songModelToSong(s, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playShuffled(songs);
  }

  /// Play a specific track
  Future<void> _playTrack(SongModel track, int index) async {
    final isOffline = _offlineService.isOffline;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    int startIndex;
    if (isOffline) {
      startIndex = songsToPlay.indexWhere((s) => s.id == track.id);
      if (startIndex == -1) startIndex = 0;
    } else {
      startIndex = index;
    }

    final songs =
        songsToPlay.map((s) => songModelToSong(s, _albumInfoMap)).toList();
    unawaited(_libraryController.markPlaylistPlayed(widget.playlistId));
    await _playbackManager.playSongs(songs, startIndex: startIndex);
  }

  /// Edit playlist name/description/image
  Future<void> _editPlaylist() async {
    if (_playlist == null) return;

    final result = await showEditPlaylistDialog(context, _playlist!);

    if (result != null && mounted) {
      await _playlistService.updatePlaylist(
        id: _playlist!.id,
        name: result.name,
        description: result.description,
        customImagePath: result.newImagePath,
        clearCustomImage: result.clearCustomImage,
      );
    }
  }

  /// Delete playlist with confirmation
  Future<void> _deletePlaylist() async {
    if (_playlist == null) return;

    final isImported = _playlistService.isImportedFromServer(_playlist!.id);
    final action = await showDeletePlaylistDialog(
      context,
      _playlist!,
      isImported: isImported,
    );

    if (action == DeletePlaylistAction.cancel || !mounted) return;

    _playlistService.removeListener(_onPlaylistsChanged);

    if (isImported) {
      await _playlistService.deleteImportedPlaylist(
        _playlist!.id,
        restoreServerVersion: action == DeletePlaylistAction.restore,
      );
    } else {
      await _playlistService.deletePlaylist(_playlist!.id);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Remove a song from playlist
  Future<void> _removeSong(String songId) async {
    await _playlistService.removeSongFromPlaylist(
      playlistId: widget.playlistId,
      songId: songId,
    );
  }

  /// Reorder songs in playlist
  void _onReorder(int oldIndex, int newIndex) {
    _playlistService.reorderSongs(
      playlistId: widget.playlistId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  /// Navigate to add songs screen
  Future<void> _addSongs() async {
    List<SongModel> availableSongs = [];
    try {
      final allSongs = await _connectionService.libraryReadFacade.getSongs();
      final existingSongIds = _playlist?.songIds.toSet() ?? {};
      availableSongs =
          allSongs.where((song) => !existingSongIds.contains(song.id)).toList();
      availableSongs.sort((a, b) => a.title.compareTo(b.title));
    } catch (e) {
      print('[PlaylistDetailScreen] Error fetching songs: $e');
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddToPlaylistScreen(
          playlistId: widget.playlistId,
          playlistName: _playlist?.name ?? 'Playlist',
          availableSongs: availableSongs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? ErrorState(
                  message: _errorMessage!,
                  onRetry: _loadPlaylist,
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_playlist == null) {
      return const Center(child: Text('No playlist data'));
    }

    final baseUrl = _connectionService.apiClient?.baseUrl;
    // Square flexible region (matches library playlist cards) to avoid letterboxing.
    final expandedArtHeight =
        MediaQuery.sizeOf(context).width.clamp(200.0, 600.0);

    return CustomScrollView(
      slivers: [
        // App bar with playlist icon
        SliverAppBar(
          expandedHeight: expandedArtHeight,
          pinned: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editPlaylist,
              tooltip: 'Edit Playlist',
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _deletePlaylist();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Playlist',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: PlaylistHeader(
              playlist: _playlist,
              songs: _songs,
              baseUrl: baseUrl,
            ),
          ),
        ),

        // Playlist info section
        SliverToBoxAdapter(
          child: PlaylistInfoSection(
            playlist: _playlist!,
            songs: _songs,
          ),
        ),

        // Action buttons
        SliverToBoxAdapter(
          child: PlaylistActionButtons(
            hasSongs: _songs.isNotEmpty,
            canReorder: _songs.length > 1,
            isReorderMode: _isReorderMode,
            onPlay: _playAll,
            onShuffle: _shuffleAll,
            onToggleReorder: () =>
                setState(() => _isReorderMode = !_isReorderMode),
            onAddSongs: _addSongs,
          ),
        ),

        // Songs list
        if (_isSongsLoading && _songs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_songs.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyPlaylistState(),
          )
        else if (_isReorderMode)
          SliverReorderableList(
            itemCount: _songs.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final song = _songs[index];
              return ReorderableDragStartListener(
                key: ValueKey(song.id),
                index: index,
                child: ReorderListItem(
                  song: song,
                  index: index,
                  onRemove: () => _removeSong(song.id),
                ),
              );
            },
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = _songs[index];
                final isDownloaded = _downloadedSongIds.contains(song.id);
                final isOffline = _offlineService.isOffline;
                final isAvailable = !isOffline || isDownloaded;

                return SongListItem(
                  song: song,
                  index: index,
                  isAvailable: isAvailable,
                  isDownloaded: isDownloaded,
                  connectionService: _connectionService,
                  onTap: () => _playTrack(song, index),
                  onRemove: () => _removeSong(song.id),
                );
              },
              childCount: _songs.length,
            ),
          ),
        if (_isSongsLoading && _songs.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),

        // Bottom padding for mini player
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: getMiniPlayerAwareBottomPadding(context),
          ),
        ),
      ],
    );
  }
}
