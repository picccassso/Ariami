import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../screens/playlist/create_playlist_screen.dart';
import '../../services/playlist_service.dart';
import '../common/mini_player_aware_bottom_sheet.dart';

/// Bottom sheet for adding all album songs to a playlist.
class AlbumPlaylistPickerSheet extends StatefulWidget {
  final List<SongModel> albumSongs;
  final String albumTitle;

  const AlbumPlaylistPickerSheet({
    super.key,
    required this.albumSongs,
    required this.albumTitle,
  });

  @override
  State<AlbumPlaylistPickerSheet> createState() =>
      _AlbumPlaylistPickerSheetState();
}

class _AlbumPlaylistPickerSheetState extends State<AlbumPlaylistPickerSheet> {
  final PlaylistService _playlistService = PlaylistService();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _createNewPlaylist() async {
    final playlist = await CreatePlaylistScreen.show(context);
    if (playlist != null && mounted) {
      await _addAlbumToPlaylist(playlist);
    }
  }

  Future<void> _addAlbumToPlaylist(PlaylistModel playlist) async {
    setState(() => _isAdding = true);

    int addedCount = 0;
    for (final song in widget.albumSongs) {
      if (!playlist.songIds.contains(song.id)) {
        await _playlistService.addSongToPlaylist(
          playlistId: playlist.id,
          songId: song.id,
          albumId: song.albumId,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
        );
        addedCount++;
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $addedCount ${addedCount == 1 ? 'song' : 'songs'} to "${playlist.name}"',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlistService.playlists;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Add Album to Playlist',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              '${widget.albumSongs.length} songs from "${widget.albumTitle}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
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
            onTap: _isAdding ? null : _createNewPlaylist,
          ),
          const Divider(),
          Expanded(
            child: _isAdding
                ? const Center(child: CircularProgressIndicator())
                : playlists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue_music,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'No playlists yet',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                          bottom: getMiniPlayerAwareBottomPadding(context),
                        ),
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          final songsAlreadyInPlaylist = widget.albumSongs
                              .where(
                                  (song) => playlist.songIds.contains(song.id))
                              .length;
                          final allSongsInPlaylist = songsAlreadyInPlaylist ==
                              widget.albumSongs.length;

                          return ListTile(
                            leading: _buildPlaylistIcon(playlist),
                            title: Text(playlist.name),
                            subtitle: Text(
                              allSongsInPlaylist
                                  ? 'All songs already in playlist'
                                  : songsAlreadyInPlaylist > 0
                                      ? '$songsAlreadyInPlaylist/${widget.albumSongs.length} songs already added'
                                      : '${playlist.songCount} song${playlist.songCount != 1 ? 's' : ''}',
                            ),
                            trailing: allSongsInPlaylist
                                ? const Icon(Icons.check, color: Colors.green)
                                : const Icon(Icons.add),
                            onTap: () => _addAlbumToPlaylist(playlist),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistIcon(PlaylistModel playlist) {
    if (playlist.id == PlaylistService.likedSongsId) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.pink[400]!, Colors.red[700]!],
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.favorite, color: Colors.white, size: 24),
      );
    }

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
