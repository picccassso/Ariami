import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../services/offline/offline_manual_reconnect.dart';
import '../../services/playback_manager.dart';
import '../../services/quality/quality_settings_service.dart';
import '../../widgets/common/bottom_chrome_metrics.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../widgets/common/queue_action_confirmation.dart';
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
  final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = LibraryController();
    _controller.initialize();
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_trackScrollOffset);
  }

  void _trackScrollOffset() {
    if (_scrollController.hasClients) {
      _savedScrollOffset = _scrollController.offset;
    }
  }

  @override
  void dispose() {
    if (_controller.isSelectionModeActive) {
      _controller.exitSelectionMode();
    }
    _scrollController.removeListener(_trackScrollOffset);
    _scrollController.dispose();
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final shouldRestoreScroll = _controller.consumeScrollRestorePending();
    setState(() {});

    if (shouldRestoreScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(_savedScrollOffset.clamp(0, maxExtent));
      });
    }
  }

  // Action Handlers

  void _openPlaylist(PlaylistModel playlist) {
    Navigator.of(context).pushNamed('/playlist', arguments: playlist.id);
  }

  void _openAlbum(AlbumModel album) {
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
      onSelectMultiple: () {
        HapticFeedback.lightImpact();
        _controller.enterSelectionMode();
        _controller.toggleAlbumSelection(album.id);
      },
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
      onSelectMultiple: () {
        HapticFeedback.lightImpact();
        _controller.enterSelectionMode();
        _controller.togglePlaylistSelection(playlist.id);
      },
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
      await _controller.playlistService.importServerPlaylist(
        serverPlaylist,
        allSongs: _controller.state.songs,
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
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
      if (mounted) {
        showQueueActionConfirmation(context, message: 'Added to queue');
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
      if (mounted) {
        showQueueActionConfirmation(context, message: 'Added to queue');
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
    if (outcome == LibraryRefreshOutcome.navigateToReconnectScreen) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/reconnect',
        (route) => false,
      );
    }
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final isOffline = _controller.offlineService.isOffline;

    return Scaffold(
      appBar: _controller.isSelectionModeActive
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _controller.exitSelectionMode,
                tooltip: 'Cancel Selection',
              ),
              title: Text(
                '${_controller.totalSelectedCount} selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: _controller.selectAllVisible,
                  tooltip: 'Select All',
                ),
                IconButton(
                  icon: const Icon(Icons.deselect_rounded),
                  onPressed: _controller.clearSelection,
                  tooltip: 'Deselect All',
                ),
              ],
            )
          : AppBar(
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
                if (!isOffline)
                  IconButton(
                    icon: const Icon(Icons.playlist_add_check_rounded),
                    onPressed: _controller.enterSelectionMode,
                    tooltip: 'Select Multiple',
                  ),
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
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return LibraryBody(
                state: _controller.state,
                isOffline: isOffline,
                scrollController: _scrollController,
                onRefresh: _handleLibraryRefresh,
                onRetry: () => unawaited(_handleLibraryRefresh()),
                onToggleAlbumsExpanded: _controller.toggleAlbumsExpanded,
                onToggleSongsExpanded: _controller.toggleSongsExpanded,
                playlistService: _controller.playlistService,
                isGridView: _controller.state.isGridView,
                onCreatePlaylist: _createNewPlaylist,
                onShowServerPlaylists: _showServerPlaylistsSheet,
                onPlaylistTap: _controller.isSelectionModeActive
                    ? (playlist) {
                        HapticFeedback.lightImpact();
                        _controller.togglePlaylistSelection(playlist.id);
                      }
                    : _openPlaylist,
                onPlaylistLongPress: _controller.isSelectionModeActive
                    ? (playlist) {
                        HapticFeedback.lightImpact();
                        _controller.togglePlaylistSelection(playlist.id);
                      }
                    : _showPlaylistContextMenu,
                onAlbumTap: _controller.isSelectionModeActive
                    ? (album) {
                        HapticFeedback.lightImpact();
                        _controller.toggleAlbumSelection(album.id);
                      }
                    : _openAlbum,
                onAlbumLongPress: _controller.isSelectionModeActive
                    ? (album) {
                        HapticFeedback.lightImpact();
                        _controller.toggleAlbumSelection(album.id);
                      }
                    : _showAlbumContextMenu,
                onSongTap: _controller.isSelectionModeActive
                    ? (song) {
                        HapticFeedback.lightImpact();
                        _controller.toggleSongSelection(song.id);
                      }
                    : _playSong,
                onSongLongPress: _controller.isSelectionModeActive
                    ? (song) {
                        HapticFeedback.lightImpact();
                        _controller.toggleSongSelection(song.id);
                      }
                    : (song) {
                        HapticFeedback.lightImpact();
                        _controller.enterSelectionMode();
                        _controller.toggleSongSelection(song.id);
                      },
                onOfflineSongTap: _controller.isSelectionModeActive
                    ? (song) {
                        HapticFeedback.lightImpact();
                        _controller.toggleSongSelection(song.id);
                      }
                    : _playSongDirect,
                onOfflineSongLongPress: _controller.isSelectionModeActive
                    ? (song) {
                        HapticFeedback.lightImpact();
                        _controller.toggleSongSelection(song.id);
                      }
                    : (song) {
                        HapticFeedback.lightImpact();
                        _controller.enterSelectionMode();
                        _controller.toggleSongSelection(song.id);
                      },
                isSelectionMode: _controller.isSelectionModeActive,
                isBatchBarVisible: _controller.isSelectionModeActive &&
                    _controller.totalSelectedCount > 0,
                selectedPlaylistIds: _controller.selectedPlaylistIds,
                selectedAlbumIds: _controller.selectedAlbumIds,
                selectedSongIds: _controller.selectedSongIds,
              );
            },
          ),
          
          // Premium Floating Glassmorphic Batch Action Bar
          MiniPlayerScrollPaddingBuilder(
            builder: (context, bottomPadding) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final isVisible = _controller.isSelectionModeActive && _controller.totalSelectedCount > 0;
                  final batchSummary = _controller.batchDownloadSummary;
                  final hasItemsToDownload = _controller.hasBatchItemsToDownload;
                  final subtitle = batchSummary.allSaved
                      ? 'Already downloaded'
                      : batchSummary.hasPartialSkip
                          ? '${batchSummary.containerCount} items · ${batchSummary.toDownloadCount} to download'
                          : '${batchSummary.containerCount} items selected';
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: isVisible ? Curves.easeOutBack : Curves.easeInOut,
                    left: 16,
                    right: 16,
                    bottom: isVisible
                        ? bottomPadding + kBatchDownloadBarBottomGap
                        : -150,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isVisible ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !isVisible,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Batch Download',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: hasItemsToDownload
                                      ? () async {
                                          await _controller.downloadSelectedItems();
                                        }
                                      : null,
                                  icon: Icon(
                                    hasItemsToDownload
                                        ? Icons.download_rounded
                                        : Icons.download_done,
                                    color: hasItemsToDownload
                                        ? null
                                        : Colors.green,
                                  ),
                                  label: Text(
                                    hasItemsToDownload ? 'Download' : 'Downloaded',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: hasItemsToDownload
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    foregroundColor: hasItemsToDownload
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                    disabledBackgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    disabledForegroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.6),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
