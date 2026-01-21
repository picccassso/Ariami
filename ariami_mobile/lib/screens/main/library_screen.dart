import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../models/download_task.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../../services/playlist_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/download/download_manager.dart';
import '../../services/cache/cache_manager.dart';
import '../../widgets/library/collapsible_section.dart';
import '../../widgets/library/album_grid_item.dart';
import '../../widgets/library/song_list_item.dart';
import '../../widgets/library/playlist_card.dart';
import '../playlist/create_playlist_screen.dart';

/// Main library screen with collapsible sections for Playlists, Albums, and Songs
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final ConnectionService _connectionService = ConnectionService();
  final PlaybackManager _playbackManager = PlaybackManager();
  final PlaylistService _playlistService = PlaylistService();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final DownloadManager _downloadManager = DownloadManager();
  final CacheManager _cacheManager = CacheManager();

  // Online mode state (from server API)
  List<AlbumModel> _albums = [];
  List<SongModel> _songs = [];

  // Offline mode state (built from downloads)
  List<Song> _offlineSongs = [];
  bool _isOfflineMode = false; // Track which list is active

  bool _isLoading = true;
  String? _errorMessage;

  // Offline mode state
  bool _showDownloadedOnly = false;
  Set<String> _downloadedSongIds = {};
  Set<String> _cachedSongIds = {};
  Set<String> _albumsWithDownloads = {};
  Set<String> _fullyDownloadedAlbumIds = {};
  Set<String> _playlistsWithDownloads = {};
  StreamSubscription<OfflineMode>? _offlineSubscription;
  StreamSubscription<void>? _cacheSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<List<DownloadTask>>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _playlistService.loadPlaylists();
    _playlistService.addListener(_onPlaylistsChanged);
    _loadDownloadedSongs();
    _loadCachedSongs();

    // Listen to offline state changes - reload library appropriately
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      _loadLibrary(); // Reload with proper offline/online handling
    });

    // Listen to connection state changes - reload when reconnected
    _connectionSubscription = _connectionService.connectionStateStream.listen((isConnected) {
      if (isConnected) {
        print('[LibraryScreen] Connection restored - refreshing library');
        _loadLibrary(); // Reload library data from server
        _loadDownloadedSongs(); // Refresh download status
      }
    });

    // Listen to cache updates
    _cacheSubscription = _cacheManager.cacheUpdateStream.listen((_) {
      _loadCachedSongs();
    });

    // Listen to download queue changes - refresh download status when downloads complete
    _downloadSubscription = _downloadManager.queueStream.listen((_) {
      _loadDownloadedSongs();
    });
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    _offlineSubscription?.cancel();
    _connectionSubscription?.cancel();
    _cacheSubscription?.cancel();
    _downloadSubscription?.cancel();
    super.dispose();
  }

  void _onPlaylistsChanged() {
    setState(() {});
  }

  /// Load list of downloaded song IDs and albums with downloads
  Future<void> _loadDownloadedSongs() async {
    final queue = _downloadManager.queue;
    final downloadedIds = <String>{};
    final albumsWithDownloads = <String>{};
    final albumDownloadCounts = <String, int>{};

    for (final task in queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedIds.add(task.songId);
        // Use albumId directly from download task
        if (task.albumId != null) {
          albumsWithDownloads.add(task.albumId!);
          // Count downloaded songs per album
          albumDownloadCounts[task.albumId!] = 
              (albumDownloadCounts[task.albumId!] ?? 0) + 1;
        }
      }
    }

    // Determine which albums are fully downloaded
    final fullyDownloaded = <String>{};
    for (final album in _albums) {
      final downloadedCount = albumDownloadCounts[album.id] ?? 0;
      if (downloadedCount >= album.songCount && album.songCount > 0) {
        fullyDownloaded.add(album.id);
      }
    }

    // Determine which playlists have downloaded songs
    final playlistsWithDownloads = <String>{};
    for (final playlist in _playlistService.playlists) {
      for (final songId in playlist.songIds) {
        if (downloadedIds.contains(songId)) {
          playlistsWithDownloads.add(playlist.id);
          break; // At least one song downloaded, no need to check more
        }
      }
    }

    setState(() {
      _downloadedSongIds = downloadedIds;
      _albumsWithDownloads = albumsWithDownloads;
      _fullyDownloadedAlbumIds = fullyDownloaded;
      _playlistsWithDownloads = playlistsWithDownloads;
    });
  }

  /// Load list of cached song IDs
  Future<void> _loadCachedSongs() async {
    final cachedIds = <String>{};

    // Check songs from appropriate list based on mode
    if (_isOfflineMode) {
      // Check offline songs
      for (final song in _offlineSongs) {
        final isCached = await _cacheManager.isSongCached(song.id);
        if (isCached) {
          cachedIds.add(song.id);
        }
      }
    } else {
      // Check online songs
      for (final song in _songs) {
        final isCached = await _cacheManager.isSongCached(song.id);
        if (isCached) {
          cachedIds.add(song.id);
        }
      }
    }

    if (mounted) {
      setState(() {
        _cachedSongIds = cachedIds;
      });
    }
  }

  /// Load library data from server (or show downloaded content if offline)
  Future<void> _loadLibrary() async {
    // If offline mode is enabled, build library from downloaded songs
    if (_offlineService.isOfflineModeEnabled) {
      print('[LibraryScreen] Offline mode enabled - building library from downloads');
      await _loadDownloadedSongs();
      _buildLibraryFromDownloads();
      await _loadDownloadedSongs(); // Re-run to populate _fullyDownloadedAlbumIds now that _albums exists
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _showDownloadedOnly = true; // Auto-enable downloaded filter in offline mode
      });
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

      print('[LibraryScreen] Fetching library from server...');
      final library = await _connectionService.apiClient!.getLibrary();
      print('[LibraryScreen] Library loaded successfully');
      print('[LibraryScreen] Albums: ${library.albums.length}');
      print('[LibraryScreen] Songs: ${library.songs.length}');
      print('[LibraryScreen] Server playlists: ${library.serverPlaylists.length}');

      // Update PlaylistService with server playlists
      _playlistService.updateServerPlaylists(library.serverPlaylists);

      setState(() {
        _albums = library.albums;
        _songs = library.songs;
        _isOfflineMode = false; // Mark that we're in online mode with SongModel
        _isLoading = false;
        _showDownloadedOnly = false; // Reset filter when back online
      });

      // Reload downloaded songs to map them to albums
      await _loadDownloadedSongs();
    } catch (e, stackTrace) {
      print('[LibraryScreen] ERROR loading library: $e');
      print('[LibraryScreen] Stack trace: $stackTrace');

      // If it's a network/timeout error, gracefully fall back to offline mode
      // This handles the race condition when network drops before ConnectionService detects it
      if (e.toString().contains('Network error') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('SocketException')) {
        print('[LibraryScreen] Network error detected - falling back to offline mode');
        await _loadDownloadedSongs();
        _buildLibraryFromDownloads();
        setState(() {
          _isLoading = false;
          _errorMessage = null;  // Don't show error - just use offline mode
          _showDownloadedOnly = true;
        });
      } else {
        // Some other error (not network-related) - show it to user
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load library: $e';
        });
      }
    }
  }

  /// Build _offlineSongs and _albums lists from downloaded tasks for offline display
  void _buildLibraryFromDownloads() {
    final queue = _downloadManager.queue;
    final completedTasks = queue.where((t) => t.status == DownloadStatus.completed).toList();

    print('[LibraryScreen] Building library from ${completedTasks.length} downloaded songs');

    // Build songs list from download tasks - use Song objects to preserve metadata
    final songs = <Song>[];
    final albumMap = <String, List<DownloadTask>>{}; // Group songs by album

    for (final task in completedTasks) {
      // Group by album for building album list
      if (task.albumId != null) {
        albumMap.putIfAbsent(task.albumId!, () => []).add(task);
      } else {
        // Only add standalone songs (no album) to the songs list
        // Use Song object to preserve all metadata from DownloadTask
        final song = Song(
          id: task.songId,
          title: task.title,
          artist: task.artist,
          album: task.albumName,           // ✅ Preserved from DownloadTask
          albumId: task.albumId,
          albumArtist: task.albumArtist,   // ✅ Preserved from DownloadTask
          trackNumber: task.trackNumber,
          discNumber: null,                // Not stored in DownloadTask
          year: null,                      // Not stored in DownloadTask
          genre: null,                     // Not stored in DownloadTask
          duration: Duration(seconds: task.duration),
          filePath: task.songId,           // Use songId as filePath for local playback
          fileSize: task.bytesDownloaded,
          modifiedTime: DateTime.now(),
        );
        songs.add(song);
      }
    }
    
    // Build albums list from grouped songs
    final albums = <AlbumModel>[];
    for (final entry in albumMap.entries) {
      final albumId = entry.key;
      final albumTasks = entry.value;
      
      // Use first task to get album info
      final firstTask = albumTasks.first;
      
      // Calculate total duration from all songs in album
      final totalDuration = albumTasks.fold<int>(0, (sum, task) => sum + task.duration);
      
      // Use albumName if available, otherwise show artist's album (for older downloads)
      final albumTitle = firstTask.albumName ?? '${firstTask.artist} Album';
      
      // Use albumArtist if available, otherwise fall back to song artist
      // This ensures featuring artists don't show as the album artist
      final artist = firstTask.albumArtist ?? firstTask.artist;
      
      albums.add(AlbumModel(
        id: albumId,
        title: albumTitle,
        artist: artist,
        songCount: albumTasks.length,
        duration: totalDuration,
      ));
    }
    
    // Sort songs by title
    songs.sort((a, b) => a.title.compareTo(b.title));
    // Sort albums by title
    albums.sort((a, b) => a.title.compareTo(b.title));

    setState(() {
      _offlineSongs = songs;  // Use offline list for Song objects
      _albums = albums;
      _isOfflineMode = true;  // Mark that we're in offline mode
    });

    print('[LibraryScreen] Built ${songs.length} songs and ${albums.length} albums from downloads');
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = _offlineService.isOffline;

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
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
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
              _showDownloadedOnly ? Icons.download_done : Icons.download_outlined,
              color: _showDownloadedOnly ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () {
              setState(() {
                _showDownloadedOnly = !_showDownloadedOnly;
              });
            },
            tooltip: _showDownloadedOnly ? 'Show All Songs' : 'Show Downloaded Only',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isOffline ? null : _loadLibrary,
            tooltip: 'Refresh Library',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    // Check if library is empty (consider both online and offline lists)
    final songsEmpty = _isOfflineMode ? _offlineSongs.isEmpty : _songs.isEmpty;
    if (_playlistService.playlists.isEmpty && _albums.isEmpty && songsEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadLibrary,
      child: CustomScrollView(
        slivers: [
          // Playlists Section
          SliverToBoxAdapter(
            child: CollapsibleSection(
              title: 'Playlists',
              initiallyExpanded: true,
              persistenceKey: 'library_section_playlists',
              child: _buildPlaylistsGrid(),
            ),
          ),

          // Albums Section
          SliverToBoxAdapter(
            child: CollapsibleSection(
              title: 'Albums',
              initiallyExpanded: true,
              persistenceKey: 'library_section_albums',
              child: _buildAlbumsGrid(),
            ),
          ),

          // Songs Section
          SliverToBoxAdapter(
            child: CollapsibleSection(
              title: 'Songs',
              initiallyExpanded: false,
              persistenceKey: 'library_section_songs',
              child: _buildSongsList(),
            ),
          ),

          // Bottom padding to prevent content from being hidden behind mini player + nav bar
          // Mini player: 60px + Download bar: 4px + Nav bar height
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: 64 + kBottomNavigationBarHeight,
            ),
          ),
        ],
      ),
    );
  }

  /// Get artwork IDs for a playlist's artwork collage
  /// Returns up to 4 unique IDs from the playlist's songs
  /// - Album songs: returns albumId
  /// - Standalone songs: returns "song_{songId}" prefix
  List<String> _getPlaylistArtworkIds(PlaylistModel playlist) {
    final artworkIds = <String>[];
    for (final songId in playlist.songIds) {
      final albumId = playlist.songAlbumIds[songId];
      if (albumId != null) {
        // Song belongs to an album - use album ID
        if (!artworkIds.contains(albumId)) {
          artworkIds.add(albumId);
        }
      } else {
        // Standalone song - use song ID with prefix
        final songArtworkId = 'song_$songId';
        if (!artworkIds.contains(songArtworkId)) {
          artworkIds.add(songArtworkId);
        }
      }
      if (artworkIds.length >= 4) break;
    }
    return artworkIds;
  }

  /// Build playlists grid
  Widget _buildPlaylistsGrid() {
    // Separate Liked Songs from regular playlists
    final likedSongsPlaylist = _playlistService.getPlaylist(PlaylistService.likedSongsId);
    final regularPlaylists = _playlistService.playlists
        .where((p) => p.id != PlaylistService.likedSongsId)
        .toList();

    // Check if there are visible server playlists to import
    final hasServerPlaylists = _playlistService.hasVisibleServerPlaylists;

    if (regularPlaylists.isEmpty && likedSongsPlaylist == null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.75,
          children: [
            CreatePlaylistCard(
              onTap: _createNewPlaylist,
            ),
            if (hasServerPlaylists)
              ImportFromServerCard(
                serverPlaylistCount: _playlistService.visibleServerPlaylists.length,
                onTap: _showServerPlaylistsSheet,
              ),
          ],
        ),
      );
    }

    // Calculate total item count: Create New + Import (if server playlists) + Liked Songs (if exists) + regular playlists
    int itemCount = 1; // Create New
    if (hasServerPlaylists) {
      itemCount++; // Import from Server
    }
    if (likedSongsPlaylist != null && likedSongsPlaylist.songIds.isNotEmpty) {
      itemCount++; // Liked Songs
    }
    itemCount += regularPlaylists.length; // Regular playlists

    // Playlists exist - show Create New + Import (if available) + Liked Songs (if exists) + regular playlists
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getGridColumnCount(context),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            // First item is "Create New Playlist"
            return CreatePlaylistCard(
              onTap: _createNewPlaylist,
            );
          }

          int currentIndex = 1;

          // Second item is Import from Server (if server playlists exist)
          if (hasServerPlaylists && index == currentIndex) {
            return ImportFromServerCard(
              serverPlaylistCount: _playlistService.visibleServerPlaylists.length,
              onTap: _showServerPlaylistsSheet,
            );
          }
          if (hasServerPlaylists) currentIndex++;

          // Next is Liked Songs (if it exists and has songs)
          final hasLikedSongs = likedSongsPlaylist != null &&
                                 likedSongsPlaylist.songIds.isNotEmpty;
          if (hasLikedSongs && index == currentIndex) {
            return PlaylistCard(
              playlist: likedSongsPlaylist,
              onTap: () => _openPlaylist(likedSongsPlaylist),
              onLongPress: () => _showPlaylistContextMenu(likedSongsPlaylist),
              albumIds: _getPlaylistArtworkIds(likedSongsPlaylist),
              isLikedSongs: true, // Special flag for styling
              hasDownloadedSongs: _playlistsWithDownloads.contains(likedSongsPlaylist.id),
            );
          }
          if (hasLikedSongs) currentIndex++;

          // Regular playlists start after the special items
          final playlistIndex = index - currentIndex;
          final playlist = regularPlaylists[playlistIndex];
          return PlaylistCard(
            playlist: playlist,
            onTap: () => _openPlaylist(playlist),
            onLongPress: () => _showPlaylistContextMenu(playlist),
            albumIds: _getPlaylistArtworkIds(playlist),
            isImportedFromServer: _playlistService.isRecentlyImported(playlist.id),
            hasDownloadedSongs: _playlistsWithDownloads.contains(playlist.id),
          );
        },
      ),
    );
  }

  /// Build albums grid
  Widget _buildAlbumsGrid() {
    // Filter albums if showing downloaded only
    final albumsToShow = _showDownloadedOnly
        ? _albums.where((a) => _albumsWithDownloads.contains(a.id)).toList()
        : _albums;

    if (albumsToShow.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _showDownloadedOnly
              ? 'No albums with downloaded songs'
              : 'No albums found',
          style: const TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    final isOffline = _offlineService.isOffline;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getGridColumnCount(context),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: albumsToShow.length,
        itemBuilder: (context, index) {
          final album = albumsToShow[index];
          final hasDownloads = _albumsWithDownloads.contains(album.id);
          final isAvailable = !isOffline || hasDownloads;

          return AlbumGridItem(
            album: album,
            onTap: isAvailable ? () => _openAlbum(album) : null,
            onLongPress: () => _showAlbumContextMenu(album),
            isAvailable: isAvailable,
            hasDownloadedSongs: hasDownloads,
          );
        },
      ),
    );
  }

  /// Build songs list
  Widget _buildSongsList() {
    // Use offline songs if in offline mode, otherwise use online songs
    if (_isOfflineMode) {
      return _buildOfflineSongsList();
    } else {
      return _buildOnlineSongsList();
    }
  }

  Widget _buildOnlineSongsList() {
    // Filter songs if showing downloaded only
    final songsToShow = _showDownloadedOnly
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    if (songsToShow.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: const Text(
          'No standalone songs found',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    final isOffline = _offlineService.isOffline;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: songsToShow.length,
      separatorBuilder: (context, index) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final song = songsToShow[index];
        final isDownloaded = _downloadedSongIds.contains(song.id);
        final isCached = _cachedSongIds.contains(song.id);
        final isAvailable = !isOffline || isDownloaded || isCached;

        // Lookup album info from _albums if song has albumId
        String? albumName;
        String? albumArtist;
        if (song.albumId != null) {
          final album = _albums.firstWhere(
            (a) => a.id == song.albumId,
            orElse: () => AlbumModel(
              id: '',
              title: '',
              artist: '',
              songCount: 0,
              duration: 0,
            ),
          );
          if (album.id.isNotEmpty) {
            albumName = album.title;
            albumArtist = album.artist;
          }
        }

        return SongListItem(
          song: song,
          onTap: isAvailable ? () => _playSong(song) : null,
          onLongPress: () => _showSongOptions(song),
          isDownloaded: isDownloaded,
          isCached: isCached,
          isAvailable: isAvailable,
          albumName: albumName,
          albumArtist: albumArtist,
        );
      },
    );
  }

  Widget _buildOfflineSongsList() {
    if (_offlineSongs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: const Text(
          'No offline songs available',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _offlineSongs.length,
      separatorBuilder: (context, index) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final song = _offlineSongs[index];
        final isDownloaded = _downloadedSongIds.contains(song.id);
        final isCached = _cachedSongIds.contains(song.id);

        // Convert Song to SongModel for display widget
        final songModel = SongModel(
          id: song.id,
          title: song.title,
          artist: song.artist,
          albumId: song.albumId,
          duration: song.duration.inSeconds,
          trackNumber: song.trackNumber,
        );

        return SongListItem(
          song: songModel,
          onTap: () => _playSongDirect(song), // Use Song directly
          onLongPress: () => _showOfflineSongOptions(song),
          isDownloaded: isDownloaded,
          isCached: isCached,
          isAvailable: true, // All offline songs are available
          albumName: song.album,
          albumArtist: song.albumArtist,
        );
      },
    );
  }

  void _showOfflineSongOptions(Song song) {
    // Long press handler for offline songs - menu shown in SongListItem widget
  }

  /// Attempt to reconnect and reload library
  Future<void> _retryConnection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // First try to restore connection
    final restored = await _connectionService.tryRestoreConnection();

    if (restored) {
      // Connection restored - load library
      await _loadLibrary();
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

  /// Build empty state
  Widget _buildEmptyState() {
    final isOffline = _offlineService.isOfflineModeEnabled;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOffline ? Icons.cloud_off : Icons.library_music,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            isOffline ? 'No Downloaded Music' : 'Your Music Library',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              isOffline
                  ? 'Download songs while online to listen offline'
                  : 'Add music to your desktop library to see it here',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Get grid column count based on screen width
  int _getGridColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 600) {
      return 3; // Tablet
    }
    return 2; // Phone
  }

  // ============================================================================
  // ACTION HANDLERS
  // ============================================================================

  /// Show bottom sheet with available server playlists to import
  void _showServerPlaylistsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final visiblePlaylists = _playlistService.visibleServerPlaylists;

        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_download, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Import from Server',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Folder playlists found on your server. Tap to import as a local playlist.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                // Playlist list
                Expanded(
                  child: visiblePlaylists.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 48, color: Colors.green[400]),
                              const SizedBox(height: 16),
                              Text(
                                'All playlists imported!',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: visiblePlaylists.length,
                          itemBuilder: (context, index) {
                            final serverPlaylist = visiblePlaylists[index];
                            return ListTile(
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Colors.blue[400]!, Colors.blue[700]!],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.folder, color: Colors.white),
                              ),
                              title: Text(serverPlaylist.name),
                              subtitle: Text('${serverPlaylist.songCount} songs'),
                              trailing: const Icon(Icons.download),
                              onTap: () => _importServerPlaylist(serverPlaylist),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Import a server playlist as local
  Future<void> _importServerPlaylist(ServerPlaylist serverPlaylist) async {
    Navigator.pop(context); // Close bottom sheet

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Get all songs to match IDs with metadata
      final allSongs = _songs;

      final localPlaylist = await _playlistService.importServerPlaylist(
        serverPlaylist,
        allSongs: allSongs,
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported "${localPlaylist.name}" with ${localPlaylist.songCount} songs'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _openPlaylist(localPlaylist),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e')),
        );
      }
    }
  }

  Future<void> _createNewPlaylist() async {
    final playlist = await CreatePlaylistScreen.show(context);
    if (playlist != null && mounted) {
      // Navigate to the newly created playlist using nested navigator
      Navigator.of(context).pushNamed('/playlist', arguments: playlist.id);
    }
  }

  void _openPlaylist(PlaylistModel playlist) {
    Navigator.of(context).pushNamed('/playlist', arguments: playlist.id);
  }

  void _openAlbum(AlbumModel album) {
    Navigator.of(context).pushNamed('/album', arguments: album);
  }

  // Play from SongModel (online mode) - converts to Song
  void _playSong(SongModel song) async {
    print('==========================================================');
    print('[LibraryScreen] _playSong called for: ${song.title}');
    print('[LibraryScreen] Song details - ID: ${song.id}, Artist: ${song.artist}, Duration: ${song.duration}s');
    print('==========================================================');

    // Convert SongModel to Song for playback
    // NOTE: Using song.id as filePath - desktop server uses ID as file identifier
    final playSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: null, // SongModel doesn't have album name, only albumId
      albumId: song.albumId, // Add albumId for artwork
      duration: Duration(seconds: song.duration),
      filePath: song.id, // Use ID as filePath for streaming endpoint
      fileSize: 0, // Not provided in SongModel
      modifiedTime: DateTime.now(), // Not provided in SongModel
      trackNumber: song.trackNumber,
    );

    print('[LibraryScreen] Converted to playback Song model');
    await _playSongDirect(playSong);
  }

  // Play from Song directly (offline mode) - no conversion needed
  Future<void> _playSongDirect(Song song) async {
    print('==========================================================');
    print('[LibraryScreen] _playSongDirect called for: ${song.title}');
    print('[LibraryScreen] Song details - ID: ${song.id}, Artist: ${song.artist}');
    print('[LibraryScreen] Album: ${song.album ?? "N/A"}, AlbumArtist: ${song.albumArtist ?? "N/A"}');
    print('==========================================================');

    print('[LibraryScreen] PlaybackManager instance: $_playbackManager');
    print('[LibraryScreen] About to call playSong()...');

    try {
      await _playbackManager.playSong(song);
      print('[LibraryScreen] ✅ PlaybackManager.playSong() completed successfully!');
    } catch (e, stackTrace) {
      print('[LibraryScreen] ❌ ERROR in playSong: $e');
      print('[LibraryScreen] Stack trace: $stackTrace');
    }
  }

  void _showSongOptions(SongModel song) {
    // Long press handler - menu shown in SongListItem widget
  }

  /// Show context menu for album long press
  void _showAlbumContextMenu(AlbumModel album) {
    final isFullyDownloaded = _fullyDownloadedAlbumIds.contains(album.id);
    
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          minimum: EdgeInsets.only(
            bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with album info
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[300],
                        child: album.coverArt != null
                            ? Image.network(
                                album.coverArt!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.album),
                              )
                            : const Icon(Icons.album),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            album.artist,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play Album'),
                onTap: () {
                  Navigator.pop(context);
                  _openAlbum(album);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to Queue'),
                onTap: () {
                  Navigator.pop(context);
                  _addAlbumToQueue(album);
                },
              ),
              if (isFullyDownloaded)
                const ListTile(
                  leading: Icon(Icons.check, color: Colors.white),
                  title: Text('Downloaded'),
                  enabled: false,
                )
              else
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download Album'),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAlbum(album);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Show context menu for playlist long press
  void _showPlaylistContextMenu(PlaylistModel playlist) {
    // Check if all songs in playlist are downloaded
    final isFullyDownloaded = playlist.songIds.isNotEmpty &&
        playlist.songIds.every((id) => _downloadedSongIds.contains(id));

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          minimum: EdgeInsets.only(
            bottom: 64 + kBottomNavigationBarHeight, // Mini player + download bar + nav bar
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with playlist info
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.purple[400],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.queue_music, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play Playlist'),
                onTap: () {
                  Navigator.pop(context);
                  _openPlaylist(playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Add to Queue'),
                onTap: () {
                  Navigator.pop(context);
                  _addPlaylistToQueue(playlist);
                },
              ),
              if (isFullyDownloaded)
                const ListTile(
                  leading: Icon(Icons.check, color: Colors.white),
                  title: Text('Downloaded'),
                  enabled: false,
                )
              else
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download Playlist'),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadPlaylist(playlist);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Add all songs from album to queue
  Future<void> _addAlbumToQueue(AlbumModel album) async {
    if (_connectionService.apiClient == null) return;

    try {
      final albumDetail = await _connectionService.apiClient!.getAlbumDetail(album.id);
      for (final track in albumDetail.songs) {
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
      print('[LibraryScreen] Failed to add album to queue: $e');
    }
  }

  /// Add all songs from playlist to queue
  Future<void> _addPlaylistToQueue(PlaylistModel playlist) async {
    if (_connectionService.apiClient == null) return;

    try {
      for (final songId in playlist.songIds) {
        // Find the song in our local library first
        final song = _songs.firstWhere(
          (s) => s.id == songId,
          orElse: () => SongModel(id: songId, title: 'Unknown', artist: 'Unknown', duration: 0),
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
      print('[LibraryScreen] Failed to add playlist to queue: $e');
    }
  }

  /// Download all songs from an album
  Future<void> _downloadAlbum(AlbumModel album) async {
    if (_connectionService.apiClient == null) return;

    try {
      final albumDetail = await _connectionService.apiClient!.getAlbumDetail(album.id);
      final baseUrl = _connectionService.apiClient!.baseUrl;

      // Build song data list for downloadAlbum
      final songDataList = albumDetail.songs.map((track) => {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'albumId': album.id,
        'albumName': album.title,
        'albumArtist': album.artist,
        'albumArt': album.coverArt ?? '',
        'downloadUrl': '$baseUrl/download/${track.id}',
        'duration': track.duration,
        'trackNumber': track.trackNumber,
        'fileSize': 0,
      }).toList();

      await _downloadManager.downloadAlbum(
        songs: songDataList,
        albumId: album.id,
        albumName: album.title,
        albumArtist: album.artist,
      );
    } catch (e) {
      print('[LibraryScreen] Failed to download album: $e');
    }
  }

  /// Download all songs from a playlist
  Future<void> _downloadPlaylist(PlaylistModel playlist) async {
    if (_connectionService.apiClient == null) return;

    try {
      final baseUrl = _connectionService.apiClient!.baseUrl;

      for (final songId in playlist.songIds) {
        // Try to find song in our local library, fallback to playlist's stored metadata
        final song = _songs.firstWhere(
          (s) => s.id == songId,
          orElse: () => SongModel(
            id: songId,
            title: playlist.songTitles[songId] ?? 'Unknown',
            artist: playlist.songArtists[songId] ?? 'Unknown',
            duration: playlist.songDurations[songId] ?? 0,
          ),
        );

        // Get album info if available
        final albumId = playlist.songAlbumIds[songId];
        String? albumName;
        String? albumArtist;

        // Try to find album info from local albums
        if (albumId != null) {
          final albumMatch = _albums.where((a) => a.id == albumId);
          if (albumMatch.isNotEmpty) {
            albumName = albumMatch.first.title;
            albumArtist = albumMatch.first.artist;
          }
        }

        await _downloadManager.downloadSong(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          albumId: albumId,
          albumName: albumName,
          albumArtist: albumArtist,
          albumArt: albumId != null ? '$baseUrl/artwork/$albumId' : '',
          downloadUrl: '$baseUrl/download/${song.id}',
          duration: song.duration,
          trackNumber: song.trackNumber,
          totalBytes: 0,
        );
      }
    } catch (e) {
      print('[LibraryScreen] Failed to download playlist: $e');
    }
  }
}
