import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../models/download_task.dart';
import '../../models/websocket_models.dart';
import '../../services/api/connection_service.dart';
import '../../services/download/download_manager.dart';
import '../../services/library/library_repository.dart';
import '../../services/offline/offline_copy_service.dart';
import '../../services/offline/offline_playback_service.dart';
import '../../services/playback_manager.dart';
import '../../services/playlist_service.dart';
import '../../utils/download_state_watcher.dart';
import '../../utils/downloaded_album_metadata.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/mini_player_aware_bottom_sheet.dart';
import '../main/library/library_controller.dart';
import 'add_to_playlist_screen.dart';
import 'utils/playlist_helpers.dart';
import 'widgets/widgets.dart';

part 'playlist_detail/playlist_detail_actions.dart';
part 'playlist_detail/playlist_detail_state.dart';
part 'playlist_detail/playlist_song_resolution.dart';

/// Playlist detail screen with editable header, reorderable songs, and playback actions
class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends _PlaylistDetailActionsState {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? ErrorState(
                  message: _errorMessage!,
                  onRetry: _loadPlaylist,
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_playlist == null) {
      return const Center(child: Text('No playlist data'));
    }

    final baseUrl = _connectionService.apiClient?.baseUrl;
    // Square flexible region (matches library playlist cards) to avoid letterboxing.
    final expandedArtHeight = detailHeaderHeight(context);

    return CustomScrollView(
      slivers: [
        // App bar with playlist icon
        SliverAppBar(
          expandedHeight: expandedArtHeight,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: PlaylistHeader(
              playlist: _playlist,
              songs: _songs,
              baseUrl: baseUrl,
            ),
          ),
        ),

        // Playlist info section
        SliverToBoxAdapter(
          child: PlaylistInfoSection(
            playlist: _playlist!,
            songs: _songs,
          ),
        ),

        if (_isOfflineCopy)
          const SliverToBoxAdapter(
            child: PlaylistOfflineCopyBanner(),
          ),

        // Action buttons
        SliverToBoxAdapter(
          child: PlaylistActionButtons(
            isPlaylistFullyDownloaded: _isPlaylistFullyDownloaded,
            hasSongs: _songs.isNotEmpty,
            canReorder: _songs.length > 1,
            isReorderMode: _isReorderMode,
            songIds: _songs.map((song) => song.id).toList(),
            onDownloadPlaylist: _songs.isEmpty
                ? null
                : (_isPlaylistFullyDownloaded
                    ? _confirmRemoveDownloads
                    : _downloadPlaylist),
            onCancelDownload: _cancelPlaylistDownload,
            onPlay: _playAll,
            onShuffle: _shuffleAll,
            onToggleReorder: () =>
                setState(() => _isReorderMode = !_isReorderMode),
            onAddSongs: _addSongs,
            onMoreActions: _showMoreActions,
          ),
        ),

        // Songs list
        if (_isSongsLoading && _songs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_songs.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyPlaylistState(),
          )
        else if (_isReorderMode)
          SliverReorderableList(
            itemCount: _songs.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final song = _songs[index];
              return ReorderListItem(
                key: ValueKey(song.id),
                song: song,
                index: index,
                onRemove: () => _removeSong(song.id),
              );
            },
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = _songs[index];
                final isDownloaded = _downloadedSongIds.contains(song.id);
                final isOffline = _shouldUseOfflineTracks;
                final isAvailable = !isOffline || isDownloaded;
                final albumId = song.albumId;
                final albumInfo =
                    albumId != null ? _albumInfoMap[albumId] : null;

                return SongListItem(
                  song: song,
                  index: index,
                  isAvailable: isAvailable,
                  isDownloaded: isDownloaded,
                  connectionService: _connectionService,
                  albumName: albumInfo?.name,
                  albumArtist: albumInfo?.artist,
                  onTap: () => _playTrack(song, index),
                  onRemove: () => _removeSong(song.id),
                );
              },
              childCount: _songs.length,
            ),
          ),
        if (_isSongsLoading && _songs.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),

        // Bottom padding for mini player
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: getMiniPlayerScrollBottomPadding(context),
          ),
        ),
      ],
    );
  }
}
