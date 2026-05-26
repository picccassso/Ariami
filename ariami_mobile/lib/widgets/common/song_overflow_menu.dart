import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/download/download_manager.dart';
import '../../services/playback_manager.dart';
import 'mini_player_aware_bottom_sheet.dart';

/// Per-track overflow menu (Play, Play Next, Add to Queue, Add to Playlist, Download).
class SongOverflowMenu extends StatelessWidget {
  final SongModel song;
  final bool enabled;
  final bool isDownloaded;
  final VoidCallback? onPlay;
  final String? albumName;
  final String? albumArtist;

  const SongOverflowMenu({
    super.key,
    required this.song,
    this.enabled = true,
    this.isDownloaded = false,
    this.onPlay,
    this.albumName,
    this.albumArtist,
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
