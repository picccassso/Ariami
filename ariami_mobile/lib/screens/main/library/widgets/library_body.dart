import 'package:flutter/material.dart';
import '../../../../models/api_models.dart';
import '../../../../models/song.dart';
import '../../../../services/playlist_service.dart';
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
  final VoidCallback onRefresh;
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

  const LibraryBody({
    super.key,
    required this.state,
    required this.isOffline,
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
  });

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state.errorMessage != null) {
      return LibraryErrorState(
        errorMessage: state.errorMessage!,
        onRetry: onRetry,
      );
    }

    if (state.isLibraryEmpty && playlistService.playlists.isEmpty) {
      return LibraryEmptyState(
        isOfflineMode: state.isOfflineMode || isOffline,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: state.isMixedMode
            ? _buildMixedModeSlivers(context)
            : _buildSeparateModeSlivers(context),
      ),
    );
  }

  List<Widget> _buildMixedModeSlivers(BuildContext context) {
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
        ),

      // Bottom padding for mini player
      SliverPadding(
        padding: EdgeInsets.only(
          bottom: getMiniPlayerAwareBottomPadding(context),
        ),
      ),
    ];
  }

  List<Widget> _buildSeparateModeSlivers(BuildContext context) {
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
        ),

      // Bottom padding for mini player
      SliverPadding(
        padding: EdgeInsets.only(
          bottom: getMiniPlayerAwareBottomPadding(context),
        ),
      ),
    ];
  }
}
