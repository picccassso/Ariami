import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../../services/search_service.dart';
import '../../widgets/search/search_result_song_item.dart';
import '../../widgets/search/search_result_album_item.dart';
import '../../widgets/search/recent_search_item.dart';
import '../album_detail_screen.dart';

/// Search screen with real-time search and recent searches
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ConnectionService _connectionService = ConnectionService();
  final SearchService _searchService = SearchService();
  final DebouncedSearch _debouncer = DebouncedSearch();
  final TextEditingController _searchController = TextEditingController();

  List<SongModel> _allSongs = [];
  List<AlbumModel> _allAlbums = [];
  SearchResults? _searchResults;
  List<String> _recentSearches = [];

  bool _isLoading = false;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _loadRecentSearches();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debouncer.cancel();
    super.dispose();
  }

  /// Load library data for searching
  Future<void> _loadLibrary() async {
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
          final albumDetail = await _connectionService.apiClient!.getAlbumDetail(album.id);
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

  /// Load recent searches from storage
  Future<void> _loadRecentSearches() async {
    final recent = await _searchService.getRecentSearches();
    setState(() {
      _recentSearches = recent;
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

  /// Execute search from recent searches
  Future<void> _executeRecentSearch(String query) async {
    _searchController.text = query;
    // Search will be triggered by _onSearchChanged listener
  }

  /// Clear search
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = null;
      _isSearching = false;
    });
  }

  /// Save search to recent searches
  Future<void> _saveSearch(String query) async {
    await _searchService.addRecentSearch(query);
    await _loadRecentSearches();
  }

  /// Clear all recent searches
  Future<void> _clearRecentSearches() async {
    await _searchService.clearRecentSearches();
    await _loadRecentSearches();
  }

  /// Remove specific recent search
  Future<void> _removeRecentSearch(String query) async {
    await _searchService.removeRecentSearch(query);
    await _loadRecentSearches();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search songs and albums...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey[400]),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                  )
                : null,
          ),
          style: const TextStyle(fontSize: 16),
        ),
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

    // Show search results if searching
    if (_searchController.text.isNotEmpty) {
      return _buildSearchResults();
    }

    // Show recent searches when not searching
    return _buildRecentSearches();
  }

  /// Build search results view
  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_searchResults == null || _searchResults!.isEmpty) {
      return _buildNoResultsState();
    }

    return ListView(
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
                color: Colors.grey[800],
              ),
            ),
          ),
          ..._searchResults!.songs.map((song) => SearchResultSongItem(
                song: song,
                searchQuery: _searchController.text,
                onTap: () {
                  _saveSearch(_searchController.text);
                  _playSong(song);
                },
              )),
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
                color: Colors.grey[800],
              ),
            ),
          ),
          ..._searchResults!.albums.map((album) => SearchResultAlbumItem(
                album: album,
                searchQuery: _searchController.text,
                onTap: () {
                  _saveSearch(_searchController.text);
                  _openAlbum(album);
                },
              )),
        ],
      ],
    );
  }

  /// Build recent searches view
  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
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
                'Recent Searches',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              TextButton(
                onPressed: _clearRecentSearches,
                child: const Text('Clear All'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            children: _recentSearches
                .map((query) => RecentSearchItem(
                      query: query,
                      onTap: () => _executeRecentSearch(query),
                      onRemove: () => _removeRecentSearch(query),
                    ))
                .toList(),
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
          Icon(
            Icons.search,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Search Music',
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
              'Search for songs, albums, and artists',
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

  /// Build "no results" empty state
  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'No Results Found',
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
              'Try searching with different keywords',
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
            onPressed: _loadLibrary,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTION HANDLERS
  // ============================================================================

  void _playSong(SongModel song) {
    // TODO: Connect to existing playback system from Phase 6
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing "${song.title}"'),
      ),
    );
  }

  void _openAlbum(AlbumModel album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumDetailScreen(album: album),
      ),
    );
  }
}
