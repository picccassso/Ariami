import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../models/api_models.dart';
import '../../models/download_task.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/search_service.dart';
import '../../services/playback_manager.dart';
import '../../services/download/download_manager.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../widgets/search/search_result_song_item.dart';
import '../../widgets/search/search_result_album_item.dart';

/// Search screen with real-time search and recent searches
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ConnectionService _connectionService = ConnectionService();
  final SearchService _searchService = SearchService();
  final PlaybackManager _playbackManager = PlaybackManager();
  final OfflinePlaybackService _offlineService = OfflinePlaybackService();
  final DownloadManager _downloadManager = DownloadManager();
  final DebouncedSearch _debouncer = DebouncedSearch();
  final TextEditingController _searchController = TextEditingController();

  List<SongModel> _allSongs = [];
  List<AlbumModel> _allAlbums = [];
  SearchResults? _searchResults;
  List<SongModel> _recentSongs = [];
  Set<String> _downloadedSongIds = {};

  bool _isLoading = false;
  bool _isSearching = false;
  bool _isOffline = false;
  String? _errorMessage;
  StreamSubscription<OfflineMode>? _offlineSubscription;

  @override
  void initState() {
    super.initState();
    _isOffline = _offlineService.isOfflineModeEnabled;
    _loadLibrary();
    _loadRecentSongs();
    _loadDownloadedSongIds();
    _searchController.addListener(_onSearchChanged);

    // Listen to offline state changes
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      final wasOffline = _isOffline;
      setState(() {
        _isOffline = _offlineService.isOfflineModeEnabled;
      });
      // Reload library and download status when offline state changes
      if (wasOffline != _isOffline) {
        _loadLibrary();
        _loadDownloadedSongIds();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debouncer.cancel();
    _offlineSubscription?.cancel();
    super.dispose();
  }

  /// Load library data for searching
  Future<void> _loadLibrary() async {
    // If offline mode is enabled, load downloaded songs for offline search
    if (_offlineService.isOfflineModeEnabled) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isOffline = true;
      });
      
      await _loadDownloadedSongs();
      return;
    }
    
    if (_connectionService.apiClient == null) {
      setState(() {
        _errorMessage = 'Not connected to server';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final library = await _connectionService.apiClient!.getLibrary();

      // Collect all songs: standalone songs + songs from albums
      final allSongs = <SongModel>[...library.songs];

      // Fetch songs from each album for comprehensive search
      for (final album in library.albums) {
        try {
          final albumDetail = await _connectionService.apiClient!
              .getAlbumDetail(album.id);
          allSongs.addAll(albumDetail.songs);
        } catch (e) {
          // If fetching album detail fails, skip it
          print('[SearchScreen] Failed to load album ${album.id}: $e');
        }
      }

      setState(() {
        _allSongs = allSongs;
        _allAlbums = library.albums;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load library: $e';
      });
    }
  }

  /// Load downloaded songs for offline search
  Future<void> _loadDownloadedSongs() async {
    // Get completed downloads from DownloadManager
    final downloadedTasks = _downloadManager.queue
        .where((task) => task.status == DownloadStatus.completed)
        .toList();

    // Convert DownloadTask to SongModel
    final songs = downloadedTasks.map((task) => SongModel(
      id: task.songId,
      title: task.title,
      artist: task.artist,
      albumId: task.albumId,
      duration: task.duration,
      trackNumber: task.trackNumber,
    )).toList();

    // Group songs by album to create AlbumModel entries
    final albumMap = <String, List<DownloadTask>>{};
    for (final task in downloadedTasks) {
      if (task.albumId != null && task.albumName != null) {
        albumMap.putIfAbsent(task.albumId!, () => []).add(task);
      }
    }

    // Create AlbumModel for each unique album
    final albums = albumMap.entries.map((entry) {
      final albumTasks = entry.value;
      final firstTask = albumTasks.first;
      final totalDuration = albumTasks.fold<int>(0, (sum, t) => sum + t.duration);
      
      return AlbumModel(
        id: entry.key,
        title: firstTask.albumName!,
        artist: firstTask.albumArtist ?? firstTask.artist,
        coverArt: firstTask.albumArt,
        songCount: albumTasks.length,
        duration: totalDuration,
      );
    }).toList();

    setState(() {
      _allSongs = songs;
      _allAlbums = albums;
      _isLoading = false;
    });
  }

  /// Load recent songs from storage
  Future<void> _loadRecentSongs() async {
    final recent = await _searchService.getRecentSongs();
    setState(() {
      _recentSongs = recent;
    });
  }

  /// Load downloaded song IDs for status tracking
  void _loadDownloadedSongIds() {
    final downloadedIds = <String>{};

    // Get downloaded songs from download manager
    for (final task in _downloadManager.queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedIds.add(task.songId);
      }
    }

    setState(() {
      _downloadedSongIds = downloadedIds;
    });
  }

  /// Handle search text changes with debouncing
  void _onSearchChanged() {
    final query = _searchController.text;

    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // Debounce search by 300ms
    _debouncer.run(() {
      _performSearch(query);
    });
  }

  /// Perform search with ranking
  void _performSearch(String query) {
    final results = _searchService.search(query, _allSongs, _allAlbums);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  /// Play song from recent songs
  Future<void> _playRecentSong(SongModel song) async {
    await _playSong(song);
  }

  /// Clear search
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = null;
      _isSearching = false;
    });
  }

  /// Save song to recent songs
  Future<void> _saveSong(SongModel song) async {
    await _searchService.addRecentSong(song);
    await _loadRecentSongs();
  }

  /// Clear all recent songs
  Future<void> _clearRecentSongs() async {
    await _searchService.clearRecentSongs();
    await _loadRecentSongs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Floating-style Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                   Expanded(
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: false,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: _isOffline 
                              ? 'Search downloaded music...' 
                              : 'Search songs, albums & artists',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: _clearSearch,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  if (_isOffline) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Main Content
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show "no downloaded music" state when offline with no downloads
    if (_isOffline && _allSongs.isEmpty) {
      return _buildNoDownloadsState();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    // Show search results if searching
    if (_searchController.text.isNotEmpty) {
      return _buildSearchResults();
    }

    // Show recent searches in both online AND offline modes
    return _buildRecentSearches();
  }

  /// Build search results view
  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults == null || _searchResults!.isEmpty) {
      return _buildNoResultsState();
    }

    return ListView(
      padding: EdgeInsets.only(
            bottom: getMiniPlayerAwareBottomPadding(),
      ),
      children: [
        // Songs Section
        if (_searchResults!.songs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Songs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
              ),
            ),
          ),
          ..._searchResults!.songs.map(
            (song) {
              // Lookup album info from search results
              String? albumName;
              String? albumArtist;
              if (song.albumId != null) {
                try {
                  final album = _searchResults!.albums.firstWhere(
                    (a) => a.id == song.albumId,
                  );
                  albumName = album.title;
                  albumArtist = album.artist;
                } catch (_) {
                  // Album not in search results, skip
                }
              }

              return SearchResultSongItem(
                song: song,
                searchQuery: _searchController.text,
                onTap: () {
                  _saveSong(song);
                  _playSong(song);
                },
                albumName: albumName,
                albumArtist: albumArtist,
                isDownloaded: _downloadedSongIds.contains(song.id),
                isCached: false,
                isAvailable: !_isOffline || _downloadedSongIds.contains(song.id),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        // Albums Section
        if (_searchResults!.albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Albums',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
              ),
            ),
          ),
          ..._searchResults!.albums.map(
            (album) => SearchResultAlbumItem(
              album: album,
              searchQuery: _searchController.text,
              onTap: () {
                _openAlbum(album);
              },
            ),
          ),
        ],
      ],
    );
  }

  /// Build recent songs view
  Widget _buildRecentSearches() {
    if (_recentSongs.isEmpty) {
      return _buildStartSearchingState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recently Played',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
              TextButton(
                onPressed: _clearRecentSongs,
                child: const Text('Clear All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: getMiniPlayerAwareBottomPadding(),
            ),
            itemCount: _recentSongs.length,
            itemBuilder: (context, index) {
              final song = _recentSongs[index];
              return SearchResultSongItem(
                song: song,
                searchQuery: '',
                onTap: () => _playRecentSong(song),
                isDownloaded: _downloadedSongIds.contains(song.id),
                isCached: false,
                isAvailable: !_isOffline || _downloadedSongIds.contains(song.id),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build "start searching" empty state
  Widget _buildStartSearchingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Discover Music',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              'Search for your favorite songs, albums, and artists to start listening.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Build "no results" empty state
  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Results Found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              'We couldn\'t find any matches for "${_searchController.text}".\nTry checking the spelling or use different keywords.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Build "no downloaded music" state for offline mode
  Widget _buildNoDownloadsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Downloads',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              'You haven\'t downloaded any music yet.\nConnect to the internet to download songs for offline playback.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
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
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _retryConnection, child: const Text('Retry')),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTION HANDLERS
  // ============================================================================

  Future<void> _playSong(SongModel song) async {
    // Convert SongModel to Song and play
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

  void _openAlbum(AlbumModel album) {
    Navigator.of(context).pushNamed('/album', arguments: album);
  }
}
