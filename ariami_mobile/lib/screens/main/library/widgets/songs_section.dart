import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../models/song.dart';
import '../../../../widgets/library/song_list_item.dart';
import '../library_state.dart';

/// Widget that displays the songs section.
/// Handles both online and offline modes.
class SongsSection extends StatelessWidget {
  final LibraryState state;
  final bool isOffline;
  final Function(SongModel) onSongTap;
  final Function(SongModel) onSongLongPress;
  final Function(Song) onOfflineSongTap;
  final Function(Song) onOfflineSongLongPress;

  const SongsSection({
    super.key,
    required this.state,
    required this.isOffline,
    required this.onSongTap,
    required this.onSongLongPress,
    required this.onOfflineSongTap,
    required this.onOfflineSongLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isOfflineMode) {
      return _buildOfflineSongs(context);
    }
    return _buildOnlineSongs(context);
  }

  Widget _buildOfflineSongs(BuildContext context) {
    if (state.offlineSongs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No offline songs available',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = state.offlineSongs[index];
          final isDownloaded = state.isSongDownloaded(song.id);
          final isCached = state.isSongCached(song.id);

          final songModel = SongModel(
            id: song.id,
            title: song.title,
            artist: song.artist,
            albumId: song.albumId,
            duration: song.duration.inSeconds,
            trackNumber: song.trackNumber,
          );

          return SongListItem(
            song: songModel,
            onTap: () => onOfflineSongTap(song),
            onLongPress: () => onOfflineSongLongPress(song),
            isDownloaded: isDownloaded,
            isCached: isCached,
            isAvailable: true,
            albumName: song.album,
            albumArtist: song.albumArtist,
          );
        },
        childCount: state.offlineSongs.length,
      ),
    );
  }

  Widget _buildOnlineSongs(BuildContext context) {
    final songsToShow = state.onlineSongsToShow;

    if (songsToShow.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No standalone songs found',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final albumById = <String, AlbumModel>{
      for (final album in state.albums) album.id: album,
    };

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final song = songsToShow[index];
          final isDownloaded = state.isSongDownloaded(song.id);
          final isCached = state.isSongCached(song.id);
          final isAvailable = !isOffline || isDownloaded || isCached;

          final album = song.albumId == null ? null : albumById[song.albumId!];

          return SongListItem(
            song: song,
            onTap: isAvailable ? () => onSongTap(song) : null,
            onLongPress: () => onSongLongPress(song),
            isDownloaded: isDownloaded,
            isCached: isCached,
            isAvailable: isAvailable,
            albumName: album?.title,
            albumArtist: album?.artist,
          );
        },
        childCount: songsToShow.length,
      ),
    );
  }
}
