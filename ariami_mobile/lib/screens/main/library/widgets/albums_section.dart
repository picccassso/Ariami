import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../widgets/library/album_grid_item.dart';
import '../../../../widgets/library/album_list_item.dart';
import '../library_state.dart';

/// Widget that displays the albums section in grid or list view.
class AlbumsSection extends StatelessWidget {
  final LibraryState state;
  final bool isOffline;
  final Function(AlbumModel) onAlbumTap;
  final Function(AlbumModel) onAlbumLongPress;

  const AlbumsSection({
    super.key,
    required this.state,
    required this.isOffline,
    required this.onAlbumTap,
    required this.onAlbumLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final albumsToShow = state.albumsToShow;

    if (albumsToShow.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            state.showDownloadedOnly
                ? 'No albums with downloaded songs'
                : 'No albums found',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.all(16.0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _getGridColumnCount(context),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.75,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final album = albumsToShow[index];
              final hasDownloads = state.hasAlbumDownloads(album.id);
              final isAvailable = !isOffline || hasDownloads;

              return AlbumGridItem(
                album: album,
                onTap: isAvailable ? () => onAlbumTap(album) : null,
                onLongPress: () => onAlbumLongPress(album),
                isAvailable: isAvailable,
                hasDownloadedSongs: hasDownloads,
              );
            },
            childCount: albumsToShow.length,
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final album = albumsToShow[index];
          final hasDownloads = state.hasAlbumDownloads(album.id);
          final isAvailable = !isOffline || hasDownloads;

          return AlbumListItem(
            album: album,
            onTap: isAvailable ? () => onAlbumTap(album) : null,
            onLongPress: () => onAlbumLongPress(album),
            isAvailable: isAvailable,
            hasDownloadedSongs: hasDownloads,
          );
        },
        childCount: albumsToShow.length,
      ),
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
