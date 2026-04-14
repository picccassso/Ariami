import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../../services/search_service.dart';
import '../../widgets/common/cached_artwork.dart';

class SongSelectionScreen extends StatefulWidget {
  const SongSelectionScreen({super.key});

  @override
  State<SongSelectionScreen> createState() => _SongSelectionScreenState();
}

class _SongSelectionScreenState extends State<SongSelectionScreen> {
  final ConnectionService _connectionService = ConnectionService();
  final SearchService _searchService = SearchService();
  final TextEditingController _searchController = TextEditingController();

  List<SongModel> _allSongs = [];
  List<AlbumModel> _allAlbums = [];
  List<SongModel> _filteredSongs = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final library = await _connectionService.libraryReadFacade.getLibraryBundle();
      
      setState(() {
        _allSongs = List<SongModel>.from(library.songs);
        _allAlbums = library.albums;
        _filteredSongs = _allSongs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load library: $e';
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredSongs = _allSongs;
      });
      return;
    }

    final results = _searchService.search(query, _allSongs, _allAlbums);
    setState(() {
      _filteredSongs = results.songs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Song'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLibrary,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredSongs.isEmpty) {
      return const Center(child: Text('No songs found'));
    }

    return ListView.builder(
      itemCount: _filteredSongs.length,
      itemBuilder: (context, index) {
        final song = _filteredSongs[index];
        return ListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: _SongRowArtwork(song: song),
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.pop(context, song);
          },
        );
      },
    );
  }
}

/// Matches [SearchResultSongItem] / [SongListItem] artwork: album or `song_${id}` cache key + URL.
class _SongRowArtwork extends StatelessWidget {
  const _SongRowArtwork({required this.song});

  final SongModel song;

  @override
  Widget build(BuildContext context) {
    final connectionService = ConnectionService();
    final String? artworkUrl;
    final String cacheId;

    if (song.albumId != null) {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    return CachedArtwork(
      albumId: cacheId,
      artworkUrl: artworkUrl,
      width: 48,
      height: 48,
      borderRadius: BorderRadius.circular(4),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
      sizeHint: ArtworkSizeHint.thumbnail,
    );
  }
}
