import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../models/song.dart';
import '../../../../services/playlist_service.dart';
import '../../../../widgets/common/bottom_chrome_metrics.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../../../../widgets/library/collapsible_section.dart';
import '../library_state.dart';
import 'albums_section.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'mixed_section.dart';
import 'playlists_section.dart';
import 'section_header.dart';
import 'songs_section.dart';

/// Main body widget for the library screen.
/// Coordinates all sections and handles loading/empty/error states.
class LibraryBody extends StatelessWidget {
  final LibraryState state;
  final bool isOffline;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onToggleAlbumsExpanded;
  final VoidCallback onToggleSongsExpanded;
  final PlaylistService playlistService;
  final bool isGridView;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onShowServerPlaylists;
  final void Function(PlaylistModel) onPlaylistTap;
  final void Function(PlaylistModel) onPlaylistLongPress;
  final void Function(AlbumModel) onAlbumTap;
  final void Function(AlbumModel) onAlbumLongPress;
  final void Function(SongModel) onSongTap;
  final void Function(SongModel) onSongLongPress;
  final void Function(Song) onOfflineSongTap;
  final void Function(Song) onOfflineSongLongPress;
  final bool isSelectionMode;
  final bool isBatchBarVisible;
  final Set<String> selectedPlaylistIds;
  final Set<String> selectedAlbumIds;
  final Set<String> selectedSongIds;
  final ScrollController scrollController;

  const LibraryBody({
    super.key,
    required this.state,
    required this.isOffline,
    required this.scrollController,
    required this.onRefresh,
    required this.onRetry,
    required this.onToggleAlbumsExpanded,
    required this.onToggleSongsExpanded,
    required this.playlistService,
    required this.isGridView,
    required this.onCreatePlaylist,
    required this.onShowServerPlaylists,
    required this.onPlaylistTap,
    required this.onPlaylistLongPress,
    required this.onAlbumTap,
    required this.onAlbumLongPress,
    required this.onSongTap,
    required this.onSongLongPress,
    required this.onOfflineSongTap,
    required this.onOfflineSongLongPress,
    this.isSelectionMode = false,
    this.isBatchBarVisible = false,
    this.selectedPlaylistIds = const {},
    this.selectedAlbumIds = const {},
    this.selectedSongIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (state.isLoading &&
        state.isLibraryEmpty &&
        playlistService.playlists.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state.errorMessage != null &&
        state.isLibraryEmpty &&
        playlistService.playlists.isEmpty) {
      return LibraryErrorState(
        errorMessage: state.errorMessage!,
        onRetry: onRetry,
      );
    }

    if (state.isLibraryEmpty && playlistService.playlists.isEmpty) {
      return MiniPlayerScrollPaddingBuilder(
        builder: (context, bottomPadding) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: CustomScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                ..._buildTopSlivers(),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomPadding),
                    child: LibraryEmptyState(
                      isOfflineMode: state.isOfflineMode || isOffline,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return MiniPlayerScrollPaddingBuilder(
      builder: (context, bottomPadding) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ..._buildTopSlivers(),
              ...state.isMixedMode
                  ? _buildMixedModeSlivers(bottomPadding)
                  : _buildSeparateModeSlivers(bottomPadding),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTopSlivers() {
    return [
      if (state.isRefreshing)
        const SliverToBoxAdapter(
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (state.syncWarningMessage != null)
        SliverToBoxAdapter(
          child: _SyncWarningBanner(message: state.syncWarningMessage!),
        ),
    ];
  }

  List<Widget> _buildMixedModeSlivers(double bottomPadding) {
    final effectiveBottomPadding =
        bottomPadding + (isBatchBarVisible ? kBatchDownloadBarScrollInset : 0);

    return [
      // Mixed Playlists + Albums Section
      MixedSection(
        state: state,
        isOffline: isOffline,
        playlistService: playlistService,
        isGridView: isGridView,
        onCreatePlaylist: onCreatePlaylist,
        onShowServerPlaylists: onShowServerPlaylists,
        onPlaylistTap: onPlaylistTap,
        onPlaylistLongPress: onPlaylistLongPress,
        onAlbumTap: onAlbumTap,
        onAlbumLongPress: onAlbumLongPress,
        isSelectionMode: isSelectionMode,
        selectedPlaylistIds: selectedPlaylistIds,
        selectedAlbumIds: selectedAlbumIds,
      ),

      // Songs Section
      SectionHeader(
        title: 'Songs',
        isExpanded: state.songsExpanded,
        onTap: onToggleSongsExpanded,
      ),
      if (state.songsExpanded)
        SongsSection(
          state: state,
          isOffline: isOffline,
          onSongTap: onSongTap,
          onSongLongPress: onSongLongPress,
          onOfflineSongTap: onOfflineSongTap,
          onOfflineSongLongPress: onOfflineSongLongPress,
          isSelectionMode: isSelectionMode,
          selectedSongIds: selectedSongIds,
        ),

      // Bottom padding for mini player and batch-download bar
      SliverPadding(
        padding: EdgeInsets.only(bottom: effectiveBottomPadding),
      ),
    ];
  }

  List<Widget> _buildSeparateModeSlivers(double bottomPadding) {
    final effectiveBottomPadding =
        bottomPadding + (isBatchBarVisible ? kBatchDownloadBarScrollInset : 0);

    return [
      // Playlists Section
      SliverToBoxAdapter(
        child: CollapsibleSection(
          title: 'Playlists',
          initiallyExpanded: true,
          persistenceKey: 'library_section_playlists',
          child: PlaylistsSection(
            state: state,
            playlistService: playlistService,
            isGridView: isGridView,
            onCreatePlaylist: onCreatePlaylist,
            onShowServerPlaylists: onShowServerPlaylists,
            onPlaylistTap: onPlaylistTap,
            onPlaylistLongPress: onPlaylistLongPress,
            isSelectionMode: isSelectionMode,
            selectedPlaylistIds: selectedPlaylistIds,
          ),
        ),
      ),

      // Albums Section
      SectionHeader(
        title: 'Albums',
        isExpanded: state.albumsExpanded,
        onTap: onToggleAlbumsExpanded,
      ),
      if (state.albumsExpanded)
        AlbumsSection(
          state: state,
          isOffline: isOffline,
          onAlbumTap: onAlbumTap,
          onAlbumLongPress: onAlbumLongPress,
          isSelectionMode: isSelectionMode,
          selectedAlbumIds: selectedAlbumIds,
        ),

      // Songs Section
      SectionHeader(
        title: 'Songs',
        isExpanded: state.songsExpanded,
        onTap: onToggleSongsExpanded,
      ),
      if (state.songsExpanded)
        SongsSection(
          state: state,
          isOffline: isOffline,
          onSongTap: onSongTap,
          onSongLongPress: onSongLongPress,
          onOfflineSongTap: onOfflineSongTap,
          onOfflineSongLongPress: onOfflineSongLongPress,
          isSelectionMode: isSelectionMode,
          selectedSongIds: selectedSongIds,
        ),

      // Bottom padding for mini player and batch-download bar
      SliverPadding(
        padding: EdgeInsets.only(bottom: effectiveBottomPadding),
      ),
    ];
  }
}

class _SyncWarningBanner extends StatelessWidget {
  const _SyncWarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sync_problem_rounded,
              size: 18,
              color: Colors.amber.shade700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.amber.shade100,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
