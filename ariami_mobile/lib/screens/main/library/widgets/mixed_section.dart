import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../services/playlist_service.dart';
import '../../../../widgets/library/album_grid_item.dart';
import '../../../../widgets/library/album_list_item.dart';
import '../../../../widgets/library/playlist_card.dart';
import '../../../../widgets/library/playlist_list_item.dart';
import '../library_state.dart';
import 'section_header.dart';

/// Combined widget that displays playlists and albums mixed together.
/// Items are sorted by modifiedAt date (newest first).
/// Uses SectionHeader for expand/collapse functionality.
class MixedSection extends StatefulWidget {
  final LibraryState state;
  final bool isOffline;
  final PlaylistService playlistService;
  final bool isGridView;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onShowServerPlaylists;
  final void Function(PlaylistModel) onPlaylistTap;
  final void Function(PlaylistModel) onPlaylistLongPress;
  final void Function(AlbumModel) onAlbumTap;
  final void Function(AlbumModel) onAlbumLongPress;

  const MixedSection({
    super.key,
    required this.state,
    required this.isOffline,
    required this.playlistService,
    required this.isGridView,
    required this.onCreatePlaylist,
    required this.onShowServerPlaylists,
    required this.onPlaylistTap,
    required this.onPlaylistLongPress,
    required this.onAlbumTap,
    required this.onAlbumLongPress,
  });

  @override
  State<MixedSection> createState() => _MixedSectionState();
}

class _MixedSectionState extends State<MixedSection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final mixedItems = _buildMixedItems();

    if (mixedItems.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        SectionHeader(
          title: 'Library',
          isExpanded: _isExpanded,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
        ),
        if (_isExpanded)
          widget.isGridView
              ? _buildGridView(context, mixedItems)
              : _buildListView(context, mixedItems),
      ],
    );
  }

  List<_MixedItem> _buildMixedItems() {
    final items = <_MixedItem>[];

    for (final playlist in widget.playlistService.playlists) {
      items.add(_MixedItem.playlist(
        playlist: playlist,
        sortAt: widget.state.lastPlayedForPlaylist(playlist.id) ??
            playlist.modifiedAt,
        isPinned: widget.state.isPlaylistPinned(playlist.id),
      ));
    }

    for (final album in widget.state.albumsToShow) {
      items.add(_MixedItem.album(
        album: album,
        sortAt: widget.state.lastPlayedForAlbum(album.id) ??
            album.modifiedAt ??
            album.createdAt ??
            DateTime(1970),
        isPinned: widget.state.isAlbumPinned(album.id),
      ));
    }

    items.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.sortAt.compareTo(a.sortAt);
    });

    return items;
  }

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

  Widget _buildGridView(BuildContext context, List<_MixedItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getGridColumnCount(context),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return item.when(
              playlist: (playlist) {
                final isLikedSongs = playlist.id == PlaylistService.likedSongsId;
                return PlaylistCard(
                  playlist: playlist,
                  onTap: () => widget.onPlaylistTap(playlist),
                  onLongPress: () => widget.onPlaylistLongPress(playlist),
                  albumIds: _getPlaylistArtworkIds(playlist),
                  isLikedSongs: isLikedSongs,
                  isImportedFromServer:
                      widget.playlistService.isRecentlyImported(playlist.id),
                  hasDownloadedSongs:
                      widget.state.hasPlaylistDownloads(playlist.id),
                  isPinned: item.isPinned,
                );
              },
              album: (album) {
                final hasDownloads = widget.state.hasAlbumDownloads(album.id);
                final isAvailable = !widget.isOffline || hasDownloads;
                return AlbumGridItem(
                  album: album,
                  onTap: isAvailable ? () => widget.onAlbumTap(album) : null,
                  onLongPress: () => widget.onAlbumLongPress(album),
                  isAvailable: isAvailable,
                  hasDownloadedSongs: hasDownloads,
                  isPinned: item.isPinned,
                );
              },
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildListView(BuildContext context, List<_MixedItem> items) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return item.when(
            playlist: (playlist) {
              final isLikedSongs = playlist.id == PlaylistService.likedSongsId;
              return PlaylistListItem(
                playlist: playlist,
                onTap: () => widget.onPlaylistTap(playlist),
                onLongPress: () => widget.onPlaylistLongPress(playlist),
                albumIds: _getPlaylistArtworkIds(playlist),
                isLikedSongs: isLikedSongs,
                isImportedFromServer:
                    widget.playlistService.isRecentlyImported(playlist.id),
                hasDownloadedSongs:
                    widget.state.hasPlaylistDownloads(playlist.id),
                isPinned: item.isPinned,
              );
            },
            album: (album) {
              final hasDownloads = widget.state.hasAlbumDownloads(album.id);
              final isAvailable = !widget.isOffline || hasDownloads;
              return AlbumListItem(
                album: album,
                onTap: isAvailable ? () => widget.onAlbumTap(album) : null,
                onLongPress: () => widget.onAlbumLongPress(album),
                isAvailable: isAvailable,
                hasDownloadedSongs: hasDownloads,
                isPinned: item.isPinned,
              );
            },
          );
        },
        childCount: items.length,
      ),
    );
  }

  int _getGridColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 600) {
      return 3;
    }
    return 2;
  }
}

/// Union type for mixed playlist/album items
class _MixedItem {
  final PlaylistModel? playlist;
  final AlbumModel? album;
  final DateTime sortAt;
  final bool isPinned;

  const _MixedItem._({
    this.playlist,
    this.album,
    required this.sortAt,
    this.isPinned = false,
  }) : assert(playlist != null || album != null);

  factory _MixedItem.playlist({
    required PlaylistModel playlist,
    required DateTime sortAt,
    bool isPinned = false,
  }) {
    return _MixedItem._(
      playlist: playlist,
      sortAt: sortAt,
      isPinned: isPinned,
    );
  }

  factory _MixedItem.album({
    required AlbumModel album,
    required DateTime sortAt,
    bool isPinned = false,
  }) {
    return _MixedItem._(
      album: album,
      sortAt: sortAt,
      isPinned: isPinned,
    );
  }

  T when<T>({
    required T Function(PlaylistModel playlist) playlist,
    required T Function(AlbumModel album) album,
  }) {
    if (this.playlist != null) {
      return playlist(this.playlist!);
    } else if (this.album != null) {
      return album(this.album!);
    }
    throw StateError('MixedItem has neither playlist nor album');
  }
}
