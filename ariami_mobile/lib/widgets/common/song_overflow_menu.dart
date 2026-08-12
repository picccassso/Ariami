import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/download/download_manager.dart';
import '../../services/playback_manager.dart';
import '../../services/playlist_service.dart';
import 'mini_player_aware_bottom_sheet.dart';

/// Per-track overflow menu (Play, Like, Play Next, Add to Queue, Add to
/// Playlist, Download).
class SongOverflowMenu extends StatelessWidget {
  final SongModel song;
  final bool enabled;
  final bool isDownloaded;
  final VoidCallback? onPlay;
  final String? albumName;
  final String? albumArtist;

  /// When provided, shows a "Remove from Playlist" action.
  final VoidCallback? onRemoveFromPlaylist;

  const SongOverflowMenu({
    super.key,
    required this.song,
    this.enabled = true,
    this.isDownloaded = false,
    this.onPlay,
    this.albumName,
    this.albumArtist,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const SizedBox(width: 48);
    }

    return IconButton(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      onPressed: () => _showSongMenu(context),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  void _showSongMenu(BuildContext context) {
    showAriamiSheet<void>(
      context: context,
      header: AriamiSheetHeader(
        title: song.title,
        subtitle: song.artist,
        leading: const Icon(Icons.music_note_rounded, size: 28),
      ),
      items: [
        ListTile(
          leading: const Icon(Icons.play_arrow),
          title: const Text('Play'),
          onTap: onPlay != null
              ? () {
                  Navigator.pop(context);
                  onPlay?.call();
                }
              : null,
        ),
        SongLikeMenuItem(song: song),
        ListTile(
          leading: const Icon(Icons.skip_next),
          title: const Text('Play Next'),
          onTap: () {
            Navigator.pop(context);
            _handlePlayNext();
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: const Text('Add to Queue'),
          onTap: () {
            Navigator.pop(context);
            _handleAddToQueue();
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('Add to Playlist'),
          onTap: () {
            Navigator.pop(context);
            AddToPlaylistScreen.showForSong(
              context,
              song.id,
              albumId: song.albumId,
              title: song.title,
              artist: song.artist,
              duration: song.duration,
            );
          },
        ),
        ListTile(
          leading: Icon(
            isDownloaded ? Icons.download_done : Icons.download,
            color: isDownloaded ? Colors.green : null,
          ),
          title: Text(isDownloaded ? 'Downloaded' : 'Download'),
          onTap: isDownloaded
              ? null
              : () {
                  Navigator.pop(context);
                  _handleDownload(context);
                },
        ),
        if (onRemoveFromPlaylist != null)
          ListTile(
            leading: const Icon(Icons.playlist_remove, color: Colors.red),
            title: const Text(
              'Remove from Playlist',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              Navigator.pop(context);
              onRemoveFromPlaylist?.call();
            },
          ),
      ],
    );
  }

  void _handlePlayNext() {
    PlaybackManager().playNext(_toSong());
  }

  void _handleAddToQueue() {
    PlaybackManager().addToQueue(_toSong());
  }

  Song _toSong() {
    return Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      genre: song.genre,
      album: null,
      albumId: song.albumId,
      duration: Duration(seconds: song.duration),
      filePath: song.id,
      fileSize: 0,
      modifiedTime: DateTime.now(),
      trackNumber: song.trackNumber,
    );
  }

  void _handleDownload(BuildContext context) {
    final connectionService = ConnectionService();

    if (connectionService.apiClient == null) {
      return;
    }

    DownloadManager().downloadSong(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      albumId: song.albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      albumArt: '',
      duration: song.duration,
      trackNumber: song.trackNumber,
      totalBytes: 0,
    );
  }
}

/// Menu action for adding or removing a song from the account-owned Liked
/// Songs playlist.
class SongLikeMenuItem extends StatefulWidget {
  final SongModel song;

  const SongLikeMenuItem({super.key, required this.song});

  @override
  State<SongLikeMenuItem> createState() => _SongLikeMenuItemState();
}

class _SongLikeMenuItemState extends State<SongLikeMenuItem> {
  final PlaylistService _playlistService = PlaylistService();
  late final Future<void> _playlistsLoaded;

  @override
  void initState() {
    super.initState();
    _playlistsLoaded = _playlistService.loadPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playlistService,
      builder: (context, _) {
        final isLiked = _playlistService.isLikedSong(widget.song.id);
        return ListTile(
          leading: Icon(
            isLiked
                ? Icons.thumb_down_alt_outlined
                : Icons.thumb_up_alt_outlined,
          ),
          title: Text(isLiked ? 'Dislike song' : 'Like song'),
          onTap: () {
            Navigator.pop(context);
            unawaited(_toggleLike());
          },
        );
      },
    );
  }

  Future<void> _toggleLike() async {
    await _playlistsLoaded;
    await _playlistService.toggleLikedSong(
      widget.song.id,
      widget.song.albumId,
      title: widget.song.title,
      artist: widget.song.artist,
      duration: widget.song.duration,
    );
  }
}
