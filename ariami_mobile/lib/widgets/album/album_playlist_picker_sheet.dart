import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../screens/playlist/create_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/playlist_service.dart';
import '../common/mini_player_aware_bottom_sheet.dart';

/// Result returned when the user successfully adds the album to a playlist.
class AlbumPlaylistAddResult {
  final String playlistId;
  final String playlistName;
  final List<String> addedSongIds;

  const AlbumPlaylistAddResult({
    required this.playlistId,
    required this.playlistName,
    required this.addedSongIds,
  });

  int get addedCount => addedSongIds.length;
}

/// Shows the unified "Add Album to Playlist" bottom sheet.
///
/// Returns an [AlbumPlaylistAddResult] when the user adds the album to a
/// playlist, or `null` if the sheet was dismissed without adding.
Future<AlbumPlaylistAddResult?> showAlbumPlaylistPicker({
  required BuildContext context,
  required AlbumModel album,
  required List<SongModel> songs,
  required ConnectionService connectionService,
}) {
  final resolvedCoverArt = connectionService.resolveServerUrl(album.coverArt);

  return showAriamiSheet<AlbumPlaylistAddResult>(
    context: context,
    header: AriamiSheetHeader(
      title: 'Add Album to Playlist',
      subtitle: '${songs.length} songs from "${album.title}"',
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: resolvedCoverArt != null && resolvedCoverArt.isNotEmpty
              ? Image.network(
                  resolvedCoverArt,
                  fit: BoxFit.cover,
                  headers: connectionService.authHeaders,
                  errorBuilder: (_, __, ___) => _albumPlaceholder(),
                )
              : _albumPlaceholder(),
        ),
      ),
    ),
    child: _AlbumPlaylistPickerBody(
      albumSongs: songs,
      albumTitle: album.title,
    ),
  );
}

Widget _albumPlaceholder() {
  return Container(
    color: Colors.grey[300],
    child: const Icon(Icons.album),
  );
}

class _AlbumPlaylistPickerBody extends StatefulWidget {
  final List<SongModel> albumSongs;
  final String albumTitle;

  const _AlbumPlaylistPickerBody({
    required this.albumSongs,
    required this.albumTitle,
  });

  @override
  State<_AlbumPlaylistPickerBody> createState() =>
      _AlbumPlaylistPickerBodyState();
}

class _AlbumPlaylistPickerBodyState extends State<_AlbumPlaylistPickerBody> {
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
    if (mounted) setState(() {});
  }

  Future<void> _createNewPlaylist() async {
    final playlist = await CreatePlaylistScreen.show(context);
    if (playlist != null && mounted) {
      await _addAlbumToPlaylist(playlist);
    }
  }

  Future<void> _addAlbumToPlaylist(PlaylistModel playlist) async {
    setState(() => _isAdding = true);

    final addedSongIds = <String>[];
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
        addedSongIds.add(song.id);
      }
    }

    if (mounted) {
      Navigator.pop(
        context,
        AlbumPlaylistAddResult(
          playlistId: playlist.id,
          playlistName: playlist.name,
          addedSongIds: addedSongIds,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdding) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final playlists = _playlistService.playlists;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const Divider(height: 1),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
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
        else
          for (final playlist in playlists)
            _buildPlaylistTile(playlist),
      ],
    );
  }

  Widget _buildPlaylistTile(PlaylistModel playlist) {
    final songsAlreadyInPlaylist = widget.albumSongs
        .where((song) => playlist.songIds.contains(song.id))
        .length;
    final allSongsInPlaylist =
        songsAlreadyInPlaylist == widget.albumSongs.length;

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
      onTap: allSongsInPlaylist ? null : () => _addAlbumToPlaylist(playlist),
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
        color: colors[colorIndex.abs()],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.queue_music, color: Colors.white, size: 24),
    );
  }
}
