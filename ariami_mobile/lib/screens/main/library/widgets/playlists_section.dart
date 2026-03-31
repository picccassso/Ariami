import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../services/playlist_service.dart';
import '../../../../widgets/library/playlist_card.dart';
import '../../../../widgets/library/playlist_list_item.dart';
import '../../../../widgets/library/special_list_items.dart';
import '../library_state.dart';

/// Widget that displays the playlists section in grid or list view.
class PlaylistsSection extends StatelessWidget {
  final LibraryState state;
  final PlaylistService playlistService;
  final bool isGridView;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onShowServerPlaylists;
  final Function(PlaylistModel) onPlaylistTap;
  final Function(PlaylistModel) onPlaylistLongPress;

  const PlaylistsSection({
    super.key,
    required this.state,
    required this.playlistService,
    required this.isGridView,
    required this.onCreatePlaylist,
    required this.onShowServerPlaylists,
    required this.onPlaylistTap,
    required this.onPlaylistLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (isGridView) {
      return _buildPlaylistsGrid(context);
    }
    return _buildPlaylistsList(context);
  }

  /// Get artwork IDs for a playlist's artwork collage
  List<String> _getPlaylistArtworkIds(PlaylistModel playlist) {
    final artworkIds = <String>[];
    final seenPrimaryIds = <String>{};

    for (final songId in playlist.songIds) {
      final albumId = playlist.songAlbumIds[songId];
      if (albumId != null && albumId.isNotEmpty) {
        final primaryId = 'a:$albumId';
        if (seenPrimaryIds.add(primaryId)) {
          artworkIds.add('a:$albumId|s:$songId');
        }
      } else {
        final primaryId = 's:$songId';
        if (seenPrimaryIds.add(primaryId)) {
          artworkIds.add(primaryId);
        }
      }
      if (artworkIds.length >= 4) break;
    }

    return artworkIds;
  }

  List<PlaylistModel> _sortedRegularPlaylists() {
    final list = playlistService.playlists
        .where((p) => p.id != PlaylistService.likedSongsId)
        .toList();
    list.sort((a, b) {
      final aPinned = state.isPlaylistPinned(a.id);
      final bPinned = state.isPlaylistPinned(b.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return 0;
    });
    return list;
  }

  Widget _buildPlaylistsGrid(BuildContext context) {
    final likedSongsPlaylist =
        playlistService.getPlaylist(PlaylistService.likedSongsId);
    final regularPlaylists = _sortedRegularPlaylists();
    final hasServerPlaylists = playlistService.hasVisibleServerPlaylists;

    if (regularPlaylists.isEmpty && likedSongsPlaylist == null) {
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
              onTap: onCreatePlaylist,
            ),
            if (hasServerPlaylists)
              ImportFromServerCard(
                serverPlaylistCount:
                    playlistService.visibleServerPlaylists.length,
                onTap: onShowServerPlaylists,
              ),
          ],
        ),
      );
    }

    int itemCount = 1; // Create New
    if (hasServerPlaylists) itemCount++; // Import from Server
    if (likedSongsPlaylist != null && likedSongsPlaylist.songIds.isNotEmpty) {
      itemCount++; // Liked Songs
    }
    itemCount += regularPlaylists.length; // Regular playlists

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
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return CreatePlaylistCard(
              onTap: onCreatePlaylist,
            );
          }

          int currentIndex = 1;

          if (hasServerPlaylists && index == currentIndex) {
            return ImportFromServerCard(
              serverPlaylistCount:
                  playlistService.visibleServerPlaylists.length,
              onTap: onShowServerPlaylists,
            );
          }
          if (hasServerPlaylists) currentIndex++;

          final hasLikedSongs = likedSongsPlaylist != null &&
              likedSongsPlaylist.songIds.isNotEmpty;
          if (hasLikedSongs && index == currentIndex) {
            return PlaylistCard(
              playlist: likedSongsPlaylist,
              onTap: () => onPlaylistTap(likedSongsPlaylist),
              onLongPress: () => onPlaylistLongPress(likedSongsPlaylist),
              albumIds: _getPlaylistArtworkIds(likedSongsPlaylist),
              isLikedSongs: true,
              hasDownloadedSongs:
                  state.hasPlaylistDownloads(likedSongsPlaylist.id),
              isPinned: state.isPlaylistPinned(likedSongsPlaylist.id),
            );
          }
          if (hasLikedSongs) currentIndex++;

          final playlistIndex = index - currentIndex;
          final playlist = regularPlaylists[playlistIndex];
          return PlaylistCard(
            playlist: playlist,
            onTap: () => onPlaylistTap(playlist),
            onLongPress: () => onPlaylistLongPress(playlist),
            albumIds: _getPlaylistArtworkIds(playlist),
            isImportedFromServer:
                playlistService.isRecentlyImported(playlist.id),
            hasDownloadedSongs: state.hasPlaylistDownloads(playlist.id),
            isPinned: state.isPlaylistPinned(playlist.id),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistsList(BuildContext context) {
    final likedSongsPlaylist =
        playlistService.getPlaylist(PlaylistService.likedSongsId);
    final regularPlaylists = _sortedRegularPlaylists();
    final hasServerPlaylists = playlistService.hasVisibleServerPlaylists;

    if (regularPlaylists.isEmpty && likedSongsPlaylist == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          children: [
            CreatePlaylistListItem(onTap: onCreatePlaylist),
            if (hasServerPlaylists)
              ImportFromServerListItem(
                serverPlaylistCount:
                    playlistService.visibleServerPlaylists.length,
                onTap: onShowServerPlaylists,
              ),
          ],
        ),
      );
    }

    int itemCount = 1; // Create New
    if (hasServerPlaylists) itemCount++; // Import from Server
    final hasLikedSongs =
        likedSongsPlaylist != null && likedSongsPlaylist.songIds.isNotEmpty;
    if (hasLikedSongs) itemCount++; // Liked Songs
    itemCount += regularPlaylists.length; // Regular playlists

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (context, index) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        if (index == 0) {
          return CreatePlaylistListItem(onTap: onCreatePlaylist);
        }

        int currentIndex = 1;

        if (hasServerPlaylists && index == currentIndex) {
          return ImportFromServerListItem(
            serverPlaylistCount: playlistService.visibleServerPlaylists.length,
            onTap: onShowServerPlaylists,
          );
        }
        if (hasServerPlaylists) currentIndex++;

        if (hasLikedSongs && index == currentIndex) {
          return PlaylistListItem(
            playlist: likedSongsPlaylist,
            onTap: () => onPlaylistTap(likedSongsPlaylist),
            onLongPress: () => onPlaylistLongPress(likedSongsPlaylist),
            albumIds: _getPlaylistArtworkIds(likedSongsPlaylist),
            isLikedSongs: true,
            hasDownloadedSongs:
                state.hasPlaylistDownloads(likedSongsPlaylist.id),
            isPinned: state.isPlaylistPinned(likedSongsPlaylist.id),
          );
        }
        if (hasLikedSongs) currentIndex++;

        final playlistIndex = index - currentIndex;
        final playlist = regularPlaylists[playlistIndex];
        return PlaylistListItem(
          playlist: playlist,
          onTap: () => onPlaylistTap(playlist),
          onLongPress: () => onPlaylistLongPress(playlist),
          albumIds: _getPlaylistArtworkIds(playlist),
          isImportedFromServer: playlistService.isRecentlyImported(playlist.id),
          hasDownloadedSongs: state.hasPlaylistDownloads(playlist.id),
          isPinned: state.isPlaylistPinned(playlist.id),
        );
      },
    );
  }

  int _getGridColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 600) {
      return 3; // Tablet
    }
    return 2; // Phone
  }
}
