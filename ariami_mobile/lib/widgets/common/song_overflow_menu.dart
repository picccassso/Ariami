import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../models/song.dart';
import '../../screens/playlist/add_to_playlist_screen.dart';
import '../../services/api/connection_service.dart';
import '../../services/download/download_manager.dart';
import '../../services/playback_manager.dart';

/// Per-track overflow menu (Play Next, Add to Queue, Add to Playlist, Download).
class SongOverflowMenu extends StatelessWidget {
  final SongModel song;
  final bool enabled;
  final String? albumName;
  final String? albumArtist;

  const SongOverflowMenu({
    super.key,
    required this.song,
    this.enabled = true,
    this.albumName,
    this.albumArtist,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const SizedBox(width: 48);
    }

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 20,
        color: Colors.grey[600],
      ),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (BuildContext context) => const [
        PopupMenuItem<String>(
          value: 'play_next',
          child: Row(
            children: [
              Icon(Icons.skip_next, size: 20),
              SizedBox(width: 12),
              Text('Play Next'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add_queue',
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 20),
              SizedBox(width: 12),
              Text('Add to Queue'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 20),
              SizedBox(width: 12),
              Text('Add to Playlist'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 20),
              SizedBox(width: 12),
              Text('Download'),
            ],
          ),
        ),
      ],
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    final playbackManager = PlaybackManager();
    final playbackSong = _toSong();

    switch (action) {
      case 'play_next':
        playbackManager.playNext(playbackSong);
        break;
      case 'add_queue':
        playbackManager.addToQueue(playbackSong);
        break;
      case 'add_playlist':
        AddToPlaylistScreen.showForSong(
          context,
          song.id,
          albumId: song.albumId,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
        );
        return;
      case 'download':
        _handleDownload(context);
        return;
      default:
        return;
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to server')),
      );
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
