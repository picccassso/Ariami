import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../services/offline/offline_manual_reconnect.dart';
import '../../services/playback_manager.dart';
import '../../services/quality/quality_settings_service.dart';
import '../playlist/create_playlist_screen.dart';
import 'library/library.dart';

/// Main library screen with collapsible sections for Playlists, Albums, and Songs.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryController _controller;
  final PlaybackManager _playbackManager = PlaybackManager();
  final QualitySettingsService _qualityService = QualitySettingsService();

  @override
  void initState() {
    super.initState();
    _controller = LibraryController();
    _controller.initialize();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // Action Handlers

  void _openPlaylist(PlaylistModel playlist) {
    unawaited(_controller.markPlaylistAccessed(playlist.id));
    Navigator.of(context).pushNamed('/playlist', arguments: playlist.id);
  }

  void _openAlbum(AlbumModel album) {
    unawaited(_controller.markAlbumAccessed(album.id));
    Navigator.of(context).pushNamed('/album', arguments: album);
  }

  void _playSong(SongModel song) async {
    final playSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: null,
      albumId: song.albumId,
      duration: Duration(seconds: song.duration),
      filePath: song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: song.trackNumber,
    );
    await _playbackManager.playSong(playSong);
  }

  void _playSongDirect(Song song) async {
    await _playbackManager.playSong(song);
  }

  Future<void> _createNewPlaylist() async {
    final playlist = await CreatePlaylistScreen.show(context);
    if (playlist != null && mounted) {
      Navigator.of(context).pushNamed('/playlist', arguments: playlist.id);
    }
  }

  // Context Menu Handlers

  void _showAlbumContextMenu(AlbumModel album) {
    showAlbumContextMenu(
      context: context,
      album: album,
      connectionService: _controller.connectionService,
      isFullyDownloaded: _controller.state.isAlbumFullyDownloaded(album.id),
      isPinned: _controller.state.isAlbumPinned(album.id),
      onPlay: () => _openAlbum(album),
      onAddToQueue: () => _addAlbumToQueue(album),
      onDownload: () => _downloadAlbum(album),
      onTogglePin: () => _controller.togglePinAlbum(album.id),
    );
  }

  void _showPlaylistContextMenu(PlaylistModel playlist) {
    final isFullyDownloaded = playlist.songIds.isNotEmpty &&
        playlist.songIds.every((id) => _controller.state.isSongDownloaded(id));

    showPlaylistContextMenu(
      context: context,
      playlist: playlist,
      isFullyDownloaded: isFullyDownloaded,
      isPinned: _controller.state.isPlaylistPinned(playlist.id),
      onPlay: () => _openPlaylist(playlist),
      onAddToQueue: () => _addPlaylistToQueue(playlist),
      onDownload: () => _downloadPlaylist(playlist),
      onTogglePin: () => _controller.togglePinPlaylist(playlist.id),
    );
  }

  void _showServerPlaylistsSheet() {
    showServerPlaylistsSheet(
      context: context,
      playlistService: _controller.playlistService,
      onImportPlaylist: _importServerPlaylist,
      onImportAll: () => _importAllServerPlaylists(
        _controller.playlistService.visibleServerPlaylists,
      ),
    );
  }

  // Server Playlist Import

  Future<void> _importServerPlaylist(ServerPlaylist serverPlaylist) async {
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final localPlaylist =
          await _controller.playlistService.importServerPlaylist(
        serverPlaylist,
        allSongs: _controller.state.songs,
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Imported "${localPlaylist.name}" with ${localPlaylist.songCount} songs'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _openPlaylist(localPlaylist),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e')),
        );
      }
    }
  }

  Future<void> _importAllServerPlaylists(
      List<ServerPlaylist> serverPlaylists) async {
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _controller.playlistService.importAllServerPlaylists(
        serverPlaylists,
        allSongs: _controller.state.songs,
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e')),
        );
      }
    }
  }

  // Queue Operations

  Future<void> _addAlbumToQueue(AlbumModel album) async {
    try {
      final albumSongs = _albumSongsFor(album.id);
      for (final track in albumSongs) {
        final song = Song(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: album.title,
          albumId: track.albumId,
          duration: Duration(seconds: track.duration),
          filePath: track.id,
          fileSize: 0,
          modifiedTime: DateTime.now(),
          trackNumber: track.trackNumber,
        );
        _playbackManager.addToQueue(song);
      }
    } catch (e) {
      // Silently fail, can't let em know it failed LOL
    }
  }

  Future<void> _addPlaylistToQueue(PlaylistModel playlist) async {
    if (_controller.connectionService.apiClient == null) return;

    try {
      for (final songId in playlist.songIds) {
        final song = _controller.state.songs.firstWhere(
          (s) => s.id == songId,
          orElse: () => SongModel(
              id: songId, title: 'Unknown', artist: 'Unknown', duration: 0),
        );

        final playSong = Song(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: null,
          albumId: song.albumId,
          duration: Duration(seconds: song.duration),
          filePath: song.id,
          fileSize: 0,
          modifiedTime: DateTime.now(),
          trackNumber: song.trackNumber,
        );
        _playbackManager.addToQueue(playSong);
      }
    } catch (e) {
      // Silently fail, can't let em know it failed LOL
    }
  }

  // Download Operations

  Future<void> _downloadAlbum(AlbumModel album) async {
    try {
      final downloadQuality = _qualityService.getDownloadQuality();
      final downloadOriginal = _qualityService.getDownloadOriginal();
      final albumSongs = _albumSongsFor(album.id);

      final songDataList = albumSongs.map((track) {
        return {
          'id': track.id,
          'title': track.title,
          'artist': track.artist,
          'albumId': album.id,
          'albumName': album.title,
          'albumArtist': album.artist,
          'albumArt': album.coverArt ?? '',
          'duration': track.duration,
          'trackNumber': track.trackNumber,
          'fileSize': 0,
        };
      }).toList();

      await _controller.downloadManager.downloadAlbum(
        songs: songDataList,
        albumId: album.id,
        albumName: album.title,
        albumArtist: album.artist,
        downloadQuality: downloadQuality,
        downloadOriginal: downloadOriginal,
      );
    } catch (e) {
      // Silently fail
    }
  }

  List<SongModel> _albumSongsFor(String albumId) {
    final songs = _controller.state.songs
        .where((song) => song.albumId == albumId)
        .toList();
    songs.sort((a, b) {
      final trackCompare =
          (a.trackNumber ?? 1 << 30).compareTo(b.trackNumber ?? 1 << 30);
      if (trackCompare != 0) {
        return trackCompare;
      }
      return a.title.compareTo(b.title);
    });
    return songs;
  }

  Future<void> _downloadPlaylist(PlaylistModel playlist) async {
    if (_controller.connectionService.apiClient == null) return;

    try {
      final downloadQuality = _qualityService.getDownloadQuality();
      final downloadOriginal = _qualityService.getDownloadOriginal();

      for (final songId in playlist.songIds) {
        final song = _controller.state.songs.firstWhere(
          (s) => s.id == songId,
          orElse: () => SongModel(
            id: songId,
            title: playlist.songTitles[songId] ?? 'Unknown',
            artist: playlist.songArtists[songId] ?? 'Unknown',
            duration: playlist.songDurations[songId] ?? 0,
          ),
        );

        final albumId = playlist.songAlbumIds[songId];
        String? albumName;
        String? albumArtist;

        if (albumId != null) {
          final albumMatch =
              _controller.state.albums.where((a) => a.id == albumId);
          if (albumMatch.isNotEmpty) {
            albumName = albumMatch.first.title;
            albumArtist = albumMatch.first.artist;
          }
        }

        await _controller.downloadManager.downloadSong(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          albumId: albumId,
          albumName: albumName,
          albumArtist: albumArtist,
          albumArt: albumId != null
              ? '${_controller.connectionService.apiClient!.baseUrl}/artwork/$albumId'
              : '',
          downloadQuality: downloadQuality,
          downloadOriginal: downloadOriginal,
          duration: song.duration,
          trackNumber: song.trackNumber,
          totalBytes: 0,
        );
      }
    } catch (e) {
      // Silently fail
    }
  }

  // Retry/Refresh (same reconnect + load path as pull-to-refresh and Settings)

  Future<void> _handleLibraryRefresh() async {
    final outcome = await _controller.refreshLibrary();
    if (!mounted) return;
    switch (outcome) {
      case LibraryRefreshOutcome.ok:
        break;
      case LibraryRefreshOutcome.showSessionExpiredSnack:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please log in to reconnect.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;
      case LibraryRefreshOutcome.showManualReconnectFailedSnack:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot connect to server. Staying in offline mode.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;
      case LibraryRefreshOutcome.navigateToReconnectScreen:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/reconnect',
          (route) => false,
        );
        break;
    }
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final isOffline = _controller.offlineService.isOffline;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Text('Library'),
            if (isOffline) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Filter toggle for downloaded songs
          IconButton(
            icon: Icon(
              _controller.state.showDownloadedOnly
                  ? Icons.check_circle_rounded
                  : Icons.arrow_circle_down_rounded,
              color: _controller.state.showDownloadedOnly
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: _controller.toggleShowDownloadedOnly,
            tooltip: _controller.state.showDownloadedOnly
                ? 'Show All Songs'
                : 'Show Downloaded Only',
          ),
          IconButton(
            icon: Icon(
              _controller.state.isGridView
                  ? Icons.list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: _controller.toggleViewMode,
            tooltip: _controller.state.isGridView
                ? 'Switch to List View'
                : 'Switch to Grid View',
          ),
          // Mixed mode toggle
          IconButton(
            icon: Icon(
              _controller.state.isMixedMode
                  ? Icons.view_agenda_rounded
                  : Icons.all_inclusive_rounded,
            ),
            onPressed: _controller.toggleMixedMode,
            tooltip: _controller.state.isMixedMode
                ? 'Separate Playlists & Albums'
                : 'Mix Playlists & Albums',
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            onPressed: _handleLibraryRefresh,
            tooltip: 'Refresh Library',
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return LibraryBody(
            state: _controller.state,
            isOffline: isOffline,
            onRefresh: _handleLibraryRefresh,
            onRetry: () => unawaited(_handleLibraryRefresh()),
            onToggleAlbumsExpanded: _controller.toggleAlbumsExpanded,
            onToggleSongsExpanded: _controller.toggleSongsExpanded,
            playlistService: _controller.playlistService,
            isGridView: _controller.state.isGridView,
            onCreatePlaylist: _createNewPlaylist,
            onShowServerPlaylists: _showServerPlaylistsSheet,
            onPlaylistTap: _openPlaylist,
            onPlaylistLongPress: _showPlaylistContextMenu,
            onAlbumTap: _openAlbum,
            onAlbumLongPress: _showAlbumContextMenu,
            onSongTap: _playSong,
            onSongLongPress: (_) {},
            onOfflineSongTap: _playSongDirect,
            onOfflineSongLongPress: (_) {},
          );
        },
      ),
    );
  }
}
