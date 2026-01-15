import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../models/download_task.dart';
import '../../services/api/connection_service.dart';
import '../../services/playlist_service.dart';
import '../../services/playback_manager.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/download/download_manager.dart';
import '../../widgets/common/cached_artwork.dart';
import 'add_to_playlist_screen.dart';

/// Helper to convert SongModel to Song with album info lookup
/// Uses album info map to populate album name and artist
Song _songModelToSong(SongModel s, Map<String, ({String name, String artist})> albumInfoMap) {
  String? albumName;
  String? albumArtist;

  // Lookup album info if song has albumId
  if (s.albumId != null && albumInfoMap.containsKey(s.albumId)) {
    final albumInfo = albumInfoMap[s.albumId]!;
    albumName = albumInfo.name;
    albumArtist = albumInfo.artist;
  }

  return Song(
    id: s.id,
    title: s.title,
    artist: s.artist,
    album: albumName,
    albumId: s.albumId,
    albumArtist: albumArtist,
    duration: Duration(seconds: s.duration),
    trackNumber: s.trackNumber,
    filePath: s.id, // Use song ID as placeholder
    fileSize: 0,
    modifiedTime: DateTime.now(),
  );
}

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

  PlaylistModel? _playlist;
  List<SongModel> _songs = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isReorderMode = false;
  Set<String> _downloadedSongIds = {};

  // Map of albumId to album info (name, artist) for stats tracking
  final Map<String, ({String name, String artist})> _albumInfoMap = {};

  @override
  void initState() {
    super.initState();
    _loadDownloadedSongs();
    _loadPlaylist();
    _playlistService.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    super.dispose();
  }

  void _onPlaylistsChanged() {
    // Only do a lightweight update - don't show loading state
    _refreshPlaylistData();
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
  /// Used for lightweight updates like reordering
  Future<void> _refreshPlaylistData() async {
    final playlist = _playlistService.getPlaylist(widget.playlistId);

    if (playlist == null) {
      // Playlist was deleted, go back
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Check if song IDs changed (added/removed) vs just reordered
    final currentSongIds = _songs.map((s) => s.id).toSet();
    final newSongIds = playlist.songIds.toSet();

    if (currentSongIds.length != newSongIds.length ||
        !currentSongIds.containsAll(newSongIds)) {
      // Songs were added or removed - need to resolve new songs
      final songs = await _resolveSongs(playlist.songIds);
      if (mounted) {
        setState(() {
          _playlist = playlist;
          _songs = songs;
        });
      }
    } else {
      // Just reordered - reorder our existing song objects
      final songMap = {for (var s in _songs) s.id: s};
      final reorderedSongs = playlist.songIds
          .where((id) => songMap.containsKey(id))
          .map((id) => songMap[id]!)
          .toList();

      if (mounted) {
        setState(() {
          _playlist = playlist;
          _songs = reorderedSongs;
        });
      }
    }
  }

  /// Load playlist and resolve song IDs to full song data
  Future<void> _loadPlaylist() async {
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

      // Resolve song IDs to full song data from server
      final songs = await _resolveSongs(playlist.songIds);

      setState(() {
        _playlist = playlist;
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load playlist: $e';
      });
    }
  }

  /// Resolve song IDs to SongModel objects
  /// When offline, builds from downloaded song metadata
  /// When online, fetches from server
  /// Also populates _albumInfoMap for stats tracking
  Future<List<SongModel>> _resolveSongs(List<String> songIds) async {
    if (songIds.isEmpty) {
      return [];
    }

    // Check if offline - use downloaded song metadata instead of server
    if (_offlineService.isOffline || _connectionService.apiClient == null) {
      return _resolveSongsFromDownloads(songIds);
    }

    try {
      // Get full library to find songs
      final library = await _connectionService.apiClient!.getLibrary();

      // Also get songs from albums
      final allSongs = <String, SongModel>{};

      // Add standalone songs
      for (final song in library.songs) {
        allSongs[song.id] = song;
      }

      // Get songs from each album and build album info map
      for (final album in library.albums) {
        try {
          final albumDetail =
              await _connectionService.apiClient!.getAlbumDetail(album.id);

          // Store album info for stats tracking
          _albumInfoMap[album.id] = (name: album.title, artist: album.artist);

          for (final song in albumDetail.songs) {
            allSongs[song.id] = song;
          }
        } catch (_) {
          // Skip albums that fail to load
        }
      }

      // Return songs in playlist order
      return songIds
          .where((id) => allSongs.containsKey(id))
          .map((id) => allSongs[id]!)
          .toList();
    } catch (e) {
      print('[PlaylistDetailScreen] Error resolving songs: $e');
      // Fallback to downloads if server fetch fails
      return _resolveSongsFromDownloads(songIds);
    }
  }

  /// Build SongModel objects from downloaded song metadata or stored playlist metadata
  /// Used when offline to display playlist songs
  /// Shows ALL songs - downloaded ones with full metadata, others with stored metadata (grayed out)
  List<SongModel> _resolveSongsFromDownloads(List<String> songIds) {
    final downloadedSongs = <String, SongModel>{};

    // FIRST PASS: Populate _albumInfoMap from ALL completed downloads
    // This ensures we have album info even if specific playlist songs aren't downloaded
    // but other songs from the same album are downloaded
    for (final task in _downloadManager.queue) {
      if (task.status == DownloadStatus.completed &&
          task.albumId != null &&
          task.albumName != null) {
        // Populate album info map from download task metadata
        // Use albumArtist if available, fallback to artist
        _albumInfoMap[task.albumId!] = (
          name: task.albumName!,
          artist: task.albumArtist ?? task.artist
        );
      }
    }

    // SECOND PASS: Build SongModel from each completed download task that's in the playlist
    for (final task in _downloadManager.queue) {
      if (task.status == DownloadStatus.completed) {
        downloadedSongs[task.songId] = SongModel(
          id: task.songId,
          title: task.title,
          artist: task.artist,
          albumId: task.albumId,
          duration: task.duration,
          trackNumber: task.trackNumber,
        );
      }
    }

    // Return ALL songs in playlist order
    // Downloaded songs get full metadata from download task
    // Others get metadata stored in playlist (if available)
    return songIds.map((id) {
      if (downloadedSongs.containsKey(id)) {
        return downloadedSongs[id]!;
      } else {
        // Use metadata stored in playlist for non-downloaded songs
        final albumId = _playlist?.songAlbumIds[id];
        final title = _playlist?.songTitles[id] ?? 'Unknown Song';
        final artist = _playlist?.songArtists[id] ?? 'Unknown Artist';
        final duration = _playlist?.songDurations[id] ?? 0;
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

    // Filter for offline mode
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

    final songs = songsToPlay.map((s) => _songModelToSong(s, _albumInfoMap)).toList();
    await _playbackManager.playSongs(songs, startIndex: 0);
  }

  /// Shuffle play all songs
  Future<void> _shuffleAll() async {
    if (_songs.isEmpty) return;

    // Filter for offline mode
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

    final songs = songsToPlay.map((s) => _songModelToSong(s, _albumInfoMap)).toList();
    await _playbackManager.playShuffled(songs);
  }

  /// Play a specific track
  Future<void> _playTrack(SongModel track, int index) async {
    // Filter for offline mode
    final isOffline = _offlineService.isOffline;
    final songsToPlay = isOffline
        ? _songs.where((s) => _downloadedSongIds.contains(s.id)).toList()
        : _songs;

    // Find the index of the clicked track in the filtered list
    int startIndex;
    if (isOffline) {
      startIndex = songsToPlay.indexWhere((s) => s.id == track.id);
      if (startIndex == -1) startIndex = 0;
    } else {
      startIndex = index;
    }

    final songs = songsToPlay.map((s) => _songModelToSong(s, _albumInfoMap)).toList();
    await _playbackManager.playSongs(songs, startIndex: startIndex);
  }

  /// Edit playlist name/description
  Future<void> _editPlaylist() async {
    if (_playlist == null) return;

    final nameController = TextEditingController(text: _playlist!.name);
    final descController =
        TextEditingController(text: _playlist!.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await _playlistService.updatePlaylist(
        id: _playlist!.id,
        name: nameController.text.trim(),
        description: descController.text.trim().isEmpty
            ? null
            : descController.text.trim(),
      );
    }
  }

  /// Delete playlist with confirmation
  /// For imported playlists, shows option to restore server version
  Future<void> _deletePlaylist() async {
    if (_playlist == null) return;

    final isImported = _playlistService.isImportedFromServer(_playlist!.id);

    if (isImported) {
      // Show special dialog for imported playlists
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Imported Playlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This playlist was imported from your server.'),
              const SizedBox(height: 12),
              Text(
                'What would you like to do?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'restore'),
              icon: const Icon(Icons.restore),
              label: const Text('Delete & Restore Original'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'permanent'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete Permanently'),
            ),
          ],
        ),
      );

      if (result != null && result != 'cancel' && mounted) {
        _playlistService.removeListener(_onPlaylistsChanged);
        await _playlistService.deleteImportedPlaylist(
          _playlist!.id,
          restoreServerVersion: result == 'restore',
        );
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } else {
      // Standard delete for regular playlists
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Playlist'),
          content:
              Text('Are you sure you want to delete "${_playlist!.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        // Remove listener before deleting to prevent double navigation
        _playlistService.removeListener(_onPlaylistsChanged);
        await _playlistService.deletePlaylist(_playlist!.id);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
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
    // Fetch all available songs from server
    List<SongModel> availableSongs = [];

    if (_connectionService.apiClient != null) {
      try {
        final library = await _connectionService.apiClient!.getLibrary();

        // Collect all songs (standalone + from albums)
        final allSongs = <String, SongModel>{};

        // Add standalone songs
        for (final song in library.songs) {
          allSongs[song.id] = song;
        }

        // Get songs from each album
        for (final album in library.albums) {
          try {
            final albumDetail =
                await _connectionService.apiClient!.getAlbumDetail(album.id);
            for (final song in albumDetail.songs) {
              allSongs[song.id] = song;
            }
          } catch (_) {
            // Skip albums that fail to load
          }
        }

        // Filter out songs already in playlist
        final existingSongIds = _playlist?.songIds.toSet() ?? {};
        availableSongs = allSongs.values
            .where((song) => !existingSongIds.contains(song.id))
            .toList();

        // Sort by title
        availableSongs.sort((a, b) => a.title.compareTo(b.title));
      } catch (e) {
        print('[PlaylistDetailScreen] Error fetching songs: $e');
      }
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
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadPlaylist,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_playlist == null) {
      return const Center(child: Text('No playlist data'));
    }

    return CustomScrollView(
      slivers: [
        // App bar with playlist icon
        SliverAppBar(
          expandedHeight: 200,
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
            background: _buildPlaylistHeader(),
          ),
        ),

        // Playlist info section
        SliverToBoxAdapter(
          child: _buildPlaylistInfo(),
        ),

        // Action buttons
        SliverToBoxAdapter(
          child: _buildActionButtons(),
        ),

        // Songs list (reorderable in reorder mode, regular otherwise)
        if (_songs.isEmpty)
          SliverToBoxAdapter(
            child: _buildEmptyState(),
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
                child: _buildReorderItem(song, index),
              );
            },
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = _songs[index];
                return _buildSongItem(song, index);
              },
              childCount: _songs.length,
            ),
          ),

        // Bottom padding for mini player + download bar + nav bar
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: 64 + kBottomNavigationBarHeight,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistHeader() {
    // Get unique artwork IDs from songs for artwork collage
    // - Album songs: use albumId
    // - Standalone songs: use "song_{songId}" prefix
    final artworkIds = <String>[];
    for (final song in _songs) {
      if (song.albumId != null) {
        // Song belongs to an album
        if (!artworkIds.contains(song.albumId)) {
          artworkIds.add(song.albumId!);
        }
      } else {
        // Standalone song - use song ID with prefix
        final songArtworkId = 'song_${song.id}';
        if (!artworkIds.contains(songArtworkId)) {
          artworkIds.add(songArtworkId);
        }
      }
      if (artworkIds.length >= 4) break;
    }

    // If we have artwork IDs, show collage (CachedArtwork handles offline)
    if (artworkIds.isNotEmpty) {
      return _buildArtworkCollage(artworkIds);
    }

    // Fallback to gradient with icon
    return _buildFallbackHeader();
  }

  /// Build artwork collage based on number of albums
  Widget _buildArtworkCollage(List<String> albumIds) {
    if (albumIds.length == 1) {
      // Single artwork
      return _buildHeaderArtwork(albumIds[0]);
    } else if (albumIds.length == 2 || albumIds.length == 3) {
      // Two artworks side by side - force square aspect ratio for each
      return Row(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: _buildHeaderArtwork(albumIds[0]),
            ),
          ),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: _buildHeaderArtwork(albumIds[1]),
            ),
          ),
        ],
      );
    } else {
      // Four artworks in a grid (2x2)
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildHeaderArtwork(albumIds[0]),
                ),
                Expanded(
                  child: _buildHeaderArtwork(albumIds[1]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildHeaderArtwork(albumIds[2]),
                ),
                Expanded(
                  child: _buildHeaderArtwork(albumIds[3]),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  /// Build a single artwork image for the header using CachedArtwork
  /// Handles both album IDs and standalone song IDs (prefixed with "song_")
  Widget _buildHeaderArtwork(String artworkId) {
    // Determine artwork URL based on ID type
    String? artworkUrl;
    if (artworkId.startsWith('song_')) {
      // Standalone song - use song artwork endpoint
      final songId = artworkId.substring(5); // Remove "song_" prefix
      artworkUrl = _connectionService.apiClient != null
          ? '${_connectionService.apiClient!.baseUrl}/song-artwork/$songId'
          : null;
    } else {
      // Album - use album artwork endpoint
      artworkUrl = _connectionService.apiClient != null
          ? '${_connectionService.apiClient!.baseUrl}/artwork/$artworkId'
          : null;
    }

    return CachedArtwork(
      albumId: artworkId, // Used as cache key
      artworkUrl: artworkUrl,
      fit: BoxFit.cover,
      fallback: _buildFallbackHeader(),
    );
  }

  /// Fallback gradient header with icon
  Widget _buildFallbackHeader() {
    final colorIndex = (_playlist?.name.hashCode ?? 0) % 5;
    final gradients = [
      [Colors.purple[400]!, Colors.purple[700]!],
      [Colors.blue[400]!, Colors.blue[700]!],
      [Colors.green[400]!, Colors.green[700]!],
      [Colors.orange[400]!, Colors.orange[700]!],
      [Colors.pink[400]!, Colors.pink[700]!],
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients[colorIndex],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.queue_music,
          size: 80,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPlaylistInfo() {
    final totalDuration = _songs.fold<int>(0, (sum, s) => sum + s.duration);
    final minutes = totalDuration ~/ 60;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _playlist!.name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_playlist!.description != null &&
              _playlist!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _playlist!.description!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_songs.length} song${_songs.length != 1 ? 's' : ''} • $minutes min',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          // Play All button
          Expanded(
            child: FilledButton(
              onPressed: _songs.isEmpty ? null : _playAll,
              child: const Icon(Icons.play_arrow),
            ),
          ),
          const SizedBox(width: 12),
          // Shuffle button
          Expanded(
            child: OutlinedButton(
              onPressed: _songs.isEmpty ? null : _shuffleAll,
              child: const Icon(Icons.shuffle),
            ),
          ),
          const SizedBox(width: 12),
          // Reorder toggle button
          IconButton(
            onPressed: _songs.length > 1
                ? () => setState(() => _isReorderMode = !_isReorderMode)
                : null,
            icon: Icon(_isReorderMode ? Icons.check : Icons.reorder),
            tooltip: _isReorderMode ? 'Done Reordering' : 'Reorder Songs',
            style: _isReorderMode
                ? IconButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  )
                : null,
          ),
          const SizedBox(width: 4),
          // Add songs button
          IconButton.filled(
            onPressed: _addSongs,
            icon: const Icon(Icons.add),
            tooltip: 'Add Songs',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          children: [
            Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No songs in this playlist',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add songs',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Normal song item with album artwork
  Widget _buildSongItem(SongModel song, int index) {
    final isDownloaded = _downloadedSongIds.contains(song.id);
    final isOffline = _offlineService.isOffline;
    final isAvailable = !isOffline || isDownloaded;
    final opacity = isAvailable ? 1.0 : 0.4;

    return Opacity(
      opacity: opacity,
      child: Dismissible(
        key: ValueKey('dismiss_${song.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => _removeSong(song.id),
        child: ListTile(
          leading: _buildAlbumArtWithBadge(song, isDownloaded),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isAvailable ? null : Colors.grey,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600]),
          ),
          trailing: Text(
            _formatDuration(song.duration),
            style: TextStyle(color: Colors.grey[600]),
          ),
          onTap: isAvailable ? () => _playTrack(song, index) : null,
        ),
      ),
    );
  }

  /// Build album art with download badge
  Widget _buildAlbumArtWithBadge(SongModel song, bool isDownloaded) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          _buildAlbumArt(song),
          if (isDownloaded)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.green[600],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download_done,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Reorder mode item with drag handle
  Widget _buildReorderItem(SongModel song, int index) {
    return Material(
      key: ValueKey('reorder_${song.id}'),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
          ],
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
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: () => _removeSong(song.id),
        ),
      ),
    );
  }

  /// Build album artwork or placeholder using CachedArtwork
  /// Handles both album songs and standalone songs
  Widget _buildAlbumArt(SongModel song) {
    // Determine artwork URL and cache ID based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (song.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = _connectionService.apiClient != null
          ? '${_connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = _connectionService.apiClient != null
          ? '${_connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    // Force square aspect ratio to ensure BoxFit.cover crops bars completely
    return AspectRatio(
      aspectRatio: 1.0,
      child: CachedArtwork(
        albumId: cacheId, // Used as cache key
        artworkUrl: artworkUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(4),
        fallback: _buildPlaceholder(),
      ),
    );
  }

  /// Placeholder for missing artwork
  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.music_note, color: Colors.grey),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
