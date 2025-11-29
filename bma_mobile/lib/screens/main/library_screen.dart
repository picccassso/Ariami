import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../services/api/connection_service.dart';
import '../../services/playback_manager.dart';
import '../../services/playlist_service.dart';
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

  List<AlbumModel> _albums = [];
  List<SongModel> _songs = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
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

  /// Load library data from server
  Future<void> _loadLibrary() async {
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

      setState(() {
        _albums = library.albums;
        _songs = library.songs;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('[LibraryScreen] ERROR loading library: $e');
      print('[LibraryScreen] Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load library: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLibrary,
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

    if (_playlistService.playlists.isEmpty && _albums.isEmpty && _songs.isEmpty) {
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
              child: _buildPlaylistsGrid(),
            ),
          ),

          // Albums Section
          SliverToBoxAdapter(
            child: CollapsibleSection(
              title: 'Albums',
              initiallyExpanded: true,
              child: _buildAlbumsGrid(),
            ),
          ),

          // Songs Section
          SliverToBoxAdapter(
            child: CollapsibleSection(
              title: 'Songs',
              initiallyExpanded: false,
              child: _buildSongsList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Get artwork URLs for a playlist based on its songs
  List<String> _getPlaylistArtworkUrls(PlaylistModel playlist) {
    if (_connectionService.apiClient == null) return [];

    final baseUrl = _connectionService.apiClient!.baseUrl;

    // Get unique album IDs from playlist's stored songAlbumIds (up to 4)
    final albumIds = <String>[];
    for (final songId in playlist.songIds) {
      final albumId = playlist.songAlbumIds[songId];
      if (albumId != null && !albumIds.contains(albumId)) {
        albumIds.add(albumId);
        if (albumIds.length >= 4) break;
      }
    }

    // Convert to artwork URLs
    return albumIds.map((id) => '$baseUrl/artwork/$id').toList();
  }

  /// Build playlists grid
  Widget _buildPlaylistsGrid() {
    final playlists = _playlistService.playlists;

    if (playlists.isEmpty) {
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
          ],
        ),
      );
    }

    // Playlists exist - show Create New + playlists
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
        itemCount: playlists.length + 1, // +1 for Create New
        itemBuilder: (context, index) {
          if (index == 0) {
            // First item is "Create New Playlist"
            return CreatePlaylistCard(
              onTap: _createNewPlaylist,
            );
          }

          final playlist = playlists[index - 1];
          return PlaylistCard(
            playlist: playlist,
            onTap: () => _openPlaylist(playlist),
            artworkUrls: _getPlaylistArtworkUrls(playlist),
          );
        },
      ),
    );
  }

  /// Build albums grid
  Widget _buildAlbumsGrid() {
    if (_albums.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No albums found',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

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
        itemCount: _albums.length,
        itemBuilder: (context, index) {
          final album = _albums[index];
          return AlbumGridItem(
            album: album,
            onTap: () => _openAlbum(album),
          );
        },
      ),
    );
  }

  /// Build songs list
  Widget _buildSongsList() {
    if (_songs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No standalone songs found',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _songs.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Colors.grey[300],
      ),
      itemBuilder: (context, index) {
        final song = _songs[index];
        return SongListItem(
          song: song,
          onTap: () => _playSong(song),
          onLongPress: () => _showSongOptions(song),
        );
      },
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Your Music Library',
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
              'Add music to your desktop library to see it here',
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
    print('[LibraryScreen] PlaybackManager instance: $_playbackManager');
    print('[LibraryScreen] About to call playSong()...');

    try {
      await _playbackManager.playSong(playSong);
      print('[LibraryScreen] ✅ PlaybackManager.playSong() completed successfully!');
    } catch (e, stackTrace) {
      print('[LibraryScreen] ❌ ERROR in playSong: $e');
      print('[LibraryScreen] Stack trace: $stackTrace');
    }
  }

  void _showSongOptions(SongModel song) {
    // Long press handler - menu shown in SongListItem widget
  }
}
