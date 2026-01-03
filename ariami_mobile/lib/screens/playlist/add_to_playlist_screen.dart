import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../../services/api/connection_service.dart';
import '../../services/playlist_service.dart';
import '../../widgets/common/cached_artwork.dart';
import 'create_playlist_screen.dart';

/// Screen for adding songs to a playlist
/// Can be used in two modes:
/// 1. Add a single song to playlists (songId provided)
/// 2. Browse and add songs to a specific playlist (playlistId provided)
class AddToPlaylistScreen extends StatefulWidget {
  /// Song ID to add to playlists (mode 1)
  final String? songId;

  /// Playlist ID to add songs to (mode 2)
  final String? playlistId;

  /// Playlist name for display (mode 2)
  final String? playlistName;

  /// List of songs to choose from when adding to a specific playlist
  final List<SongModel>? availableSongs;

  const AddToPlaylistScreen({
    super.key,
    this.songId,
    this.playlistId,
    this.playlistName,
    this.availableSongs,
  });

  /// Show as a bottom sheet for adding a song to playlists
  static Future<void> showForSong(
    BuildContext context,
    String songId, {
    String? albumId,
    String? title,
    String? artist,
    int? duration,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _AddSongToPlaylistsSheet(
          songId: songId,
          albumId: albumId,
          title: title,
          artist: artist,
          duration: duration,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<AddToPlaylistScreen> createState() => _AddToPlaylistScreenState();
}

class _AddToPlaylistScreenState extends State<AddToPlaylistScreen> {
  final PlaylistService _playlistService = PlaylistService();
  final Set<String> _addedSongIds = {};

  // Track song states: 'transitioning' or 'added'
  final Map<String, String> _songStates = {};
  final Map<String, Timer> _transitionTimers = {};

  @override
  void initState() {
    super.initState();
    _playlistService.loadPlaylists();
    _playlistService.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    // Cancel all active timers
    for (var timer in _transitionTimers.values) {
      timer.cancel();
    }
    _transitionTimers.clear();
    super.dispose();
  }

  void _onPlaylistsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Mode 2: Adding songs to a specific playlist
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${widget.playlistName ?? 'Playlist'}'),
      ),
      body: widget.availableSongs == null || widget.availableSongs!.isEmpty
          ? _buildNoSongsAvailable()
          : _buildSongsList(),
    );
  }

  Widget _buildNoSongsAvailable() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No songs available to add',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to server to browse songs',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSongsList() {
    return ListView.builder(
      itemCount: widget.availableSongs!.length,
      itemBuilder: (context, index) {
        final song = widget.availableSongs![index];
        final songState = _songStates[song.id];
        final isAdded = _addedSongIds.contains(song.id);

        Widget trailing;
        VoidCallback? onTap;

        if (songState == 'transitioning') {
          // Show green checkmark during transition
          trailing = const Icon(Icons.check, color: Colors.green);
          onTap = null;
        } else if (songState == 'added' || isAdded) {
          // Show red minus button for removal
          trailing = IconButton(
            icon: const Icon(Icons.remove, color: Colors.red),
            onPressed: () => _removeSongFromPlaylist(song),
          );
          onTap = () => _removeSongFromPlaylist(song);
        } else {
          // Show plus button to add
          trailing = IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addSongToPlaylist(song),
          );
          onTap = () => _addSongToPlaylist(song);
        }

        return ListTile(
          leading: _buildAlbumArt(song),
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
          trailing: trailing,
          onTap: onTap,
        );
      },
    );
  }

  /// Build album artwork or placeholder
  Widget _buildAlbumArt(SongModel song) {
    final connectionService = ConnectionService();

    // Determine artwork URL and cache ID based on whether song has albumId
    String? artworkUrl;
    String cacheId;

    if (song.albumId != null) {
      // Song belongs to an album - use album artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/artwork/${song.albumId}'
          : null;
      cacheId = song.albumId!;
    } else {
      // Standalone song - use song artwork endpoint
      artworkUrl = connectionService.apiClient != null
          ? '${connectionService.apiClient!.baseUrl}/song-artwork/${song.id}'
          : null;
      cacheId = 'song_${song.id}';
    }

    return CachedArtwork(
      albumId: cacheId, // Used as cache key
      artworkUrl: artworkUrl,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(4),
      fallback: _buildPlaceholder(),
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 24,
    );
  }

  /// Build placeholder for missing artwork
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

  Future<void> _addSongToPlaylist(SongModel song) async {
    if (widget.playlistId == null) return;

    await _playlistService.addSongToPlaylist(
      playlistId: widget.playlistId!,
      songId: song.id,
      albumId: song.albumId,
      title: song.title,
      artist: song.artist,
      duration: song.duration,
    );

    if (mounted) {
      setState(() {
        _addedSongIds.add(song.id);
        _songStates[song.id] = 'transitioning';
      });

      // Cancel any existing timer for this song
      _transitionTimers[song.id]?.cancel();

      // Start 1-second timer to show minus button
      _transitionTimers[song.id] = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _songStates[song.id] = 'added';
          });
        }
      });
    }
  }

  Future<void> _removeSongFromPlaylist(SongModel song) async {
    if (widget.playlistId == null) return;

    // Cancel any pending transition timer
    _transitionTimers[song.id]?.cancel();
    _transitionTimers.remove(song.id);

    await _playlistService.removeSongFromPlaylist(
      playlistId: widget.playlistId!,
      songId: song.id,
    );

    if (mounted) {
      setState(() {
        _addedSongIds.remove(song.id);
        _songStates.remove(song.id);
      });
    }
  }
}

/// Bottom sheet widget for adding a song to one or more playlists
class _AddSongToPlaylistsSheet extends StatefulWidget {
  final String songId;
  final String? albumId;
  final String? title;
  final String? artist;
  final int? duration;
  final ScrollController scrollController;

  const _AddSongToPlaylistsSheet({
    required this.songId,
    this.albumId,
    this.title,
    this.artist,
    this.duration,
    required this.scrollController,
  });

  @override
  State<_AddSongToPlaylistsSheet> createState() =>
      _AddSongToPlaylistsSheetState();
}

class _AddSongToPlaylistsSheetState extends State<_AddSongToPlaylistsSheet> {
  final PlaylistService _playlistService = PlaylistService();

  // Track playlist states: 'transitioning' or 'added'
  final Map<String, String> _playlistStates = {};
  final Map<String, Timer> _transitionTimers = {};

  @override
  void initState() {
    super.initState();
    _playlistService.loadPlaylists();
    _playlistService.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    // Cancel all active timers
    for (var timer in _transitionTimers.values) {
      timer.cancel();
    }
    _transitionTimers.clear();
    super.dispose();
  }

  void _onPlaylistsChanged() {
    setState(() {});
  }

  Future<void> _createNewPlaylist() async {
    final playlist = await CreatePlaylistScreen.show(context);
    if (playlist != null && mounted) {
      // Add the song to the newly created playlist
      await _playlistService.addSongToPlaylist(
        playlistId: playlist.id,
        songId: widget.songId,
        albumId: widget.albumId,
        title: widget.title,
        artist: widget.artist,
        duration: widget.duration,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _addToPlaylist(PlaylistModel playlist) async {
    // Check if song is already in playlist
    if (playlist.songIds.contains(widget.songId)) {
      return;
    }

    await _playlistService.addSongToPlaylist(
      playlistId: playlist.id,
      songId: widget.songId,
      albumId: widget.albumId,
      title: widget.title,
      artist: widget.artist,
      duration: widget.duration,
    );

    if (mounted) {
      setState(() {
        _playlistStates[playlist.id] = 'transitioning';
      });

      // Cancel any existing timer for this playlist
      _transitionTimers[playlist.id]?.cancel();

      // Start 1-second timer to show minus button
      _transitionTimers[playlist.id] = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _playlistStates[playlist.id] = 'added';
          });
        }
      });
    }
  }

  Future<void> _removeFromPlaylist(PlaylistModel playlist) async {
    // Cancel any pending transition timer
    _transitionTimers[playlist.id]?.cancel();
    _transitionTimers.remove(playlist.id);

    await _playlistService.removeSongFromPlaylist(
      playlistId: playlist.id,
      songId: widget.songId,
    );

    if (mounted) {
      setState(() {
        _playlistStates.remove(playlist.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlistService.playlists;

    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Title
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Add to Playlist',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // Create new playlist option
        ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.add, color: Colors.grey),
          ),
          title: const Text('Create New Playlist'),
          onTap: _createNewPlaylist,
        ),

        const Divider(),

        // Playlists list
        Expanded(
          child: playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No playlists yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final isInPlaylist =
                        playlist.songIds.contains(widget.songId);
                    final playlistState = _playlistStates[playlist.id];

                    Widget trailing;
                    VoidCallback? onTap;

                    if (playlistState == 'transitioning') {
                      // Show green checkmark during transition
                      trailing = const Icon(Icons.check, color: Colors.green);
                      onTap = null;
                    } else if (playlistState == 'added' || isInPlaylist) {
                      // Show red minus button for removal
                      trailing = IconButton(
                        icon: const Icon(Icons.remove, color: Colors.red),
                        onPressed: () => _removeFromPlaylist(playlist),
                      );
                      onTap = () => _removeFromPlaylist(playlist);
                    } else {
                      // Show plus icon to add
                      trailing = const Icon(Icons.add);
                      onTap = () => _addToPlaylist(playlist);
                    }

                    return ListTile(
                      leading: _buildPlaylistIcon(playlist),
                      title: Text(playlist.name),
                      subtitle: Text(
                        '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
                      ),
                      trailing: trailing,
                      onTap: onTap,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlaylistIcon(PlaylistModel playlist) {
    final colorIndex = playlist.name.hashCode % 5;
    final colors = [
      Colors.purple[400]!,
      Colors.blue[400]!,
      Colors.green[400]!,
      Colors.orange[400]!,
      Colors.pink[400]!,
    ];

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors[colorIndex],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.queue_music, color: Colors.white, size: 24),
    );
  }
}
