import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/download_task.dart';
import '../../../widgets/common/mini_player_aware_bottom_sheet.dart';
import 'downloads_controller.dart';
import 'widgets/widgets.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late final DownloadsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DownloadsController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearAllDownloads() async {
    final confirmed = await showClearDownloadsDialog(context);
    if (confirmed == true) {
      await _controller.clearAllDownloads();
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showClearCacheDialog(context);
    if (confirmed == true) {
      await _controller.clearCache();
    }
  }

  Future<void> _confirmDeleteAlbum(
    String? albumId,
    String albumName,
    int songCount,
  ) async {
    final confirmed = await showDeleteAlbumDialog(
      context,
      albumName: albumName,
      songCount: songCount,
    );
    if (confirmed == true) {
      await _controller.deleteAlbumDownloads(albumId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dm = _controller.downloadManager;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (dm.queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearAllDownloads,
              tooltip: 'Clear all downloads',
            ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _controller.initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error initializing downloads: ${snapshot.error}'),
            );
          }

          return StreamBuilder<List<DownloadTask>>(
            stream: dm.queueStream,
            initialData: dm.queue,
            builder: (context, snapshot) {
              final queue = snapshot.data ?? [];
              _controller.syncVisibleQueueState(queue);
              final state = _controller.state;

              return ListView(
                padding: EdgeInsets.only(
                  bottom: getMiniPlayerAwareBottomPadding(context),
                ),
                children: [
                  StatisticsCard(
                    isDark: isDark,
                    sizeMB: dm.getTotalDownloadedSizeMB(),
                    stats: dm.getQueueStats(),
                  ),
                  DownloadModeCard(
                    isDark: isDark,
                    downloadOriginal: state.downloadOriginal,
                    onChanged: (value) async {
                      await _controller.setDownloadOriginal(value);
                    },
                  ),
                  DownloadAllCard(
                    isDark: isDark,
                    downloadedSongCount: state.downloadedSongCount,
                    totalSongCount: state.totalSongCount,
                    downloadedAlbumCount: state.downloadedAlbumCount,
                    totalAlbumCount: state.totalAlbumCount,
                    downloadedPlaylistSongCount:
                        state.downloadedPlaylistSongCount,
                    totalPlaylistSongCount: state.totalPlaylistSongCount,
                    isLoadingCounts: state.isLoadingCounts,
                    isDownloadingAllSongs: state.isDownloadingAllSongs,
                    isDownloadingAllAlbums: state.isDownloadingAllAlbums,
                    isDownloadingAllPlaylists: state.isDownloadingAllPlaylists,
                    onDownloadAllSongs: () =>
                        unawaited(_controller.downloadAllSongs()),
                    onDownloadAllAlbums: () =>
                        unawaited(_controller.downloadAllAlbums()),
                    onDownloadAllPlaylists: () =>
                        unawaited(_controller.downloadAllPlaylists()),
                  ),
                  CacheSectionCard(
                    isDark: isDark,
                    cacheSizeMB: state.cacheSizeMB,
                    cachedSongCount: state.cachedSongCount,
                    cacheLimitMB: state.cacheLimitMB,
                    onLimitChanged: (value) {
                      _controller.setCacheLimitDuringDrag(value.round());
                    },
                    onLimitChangeEnd: (value) {
                      unawaited(_controller.commitCacheLimit(value.round()));
                    },
                    onClearCache: () => unawaited(_clearCache()),
                  ),
                  const SizedBox(height: 24),
                  DownloadQueueSection(
                    title: 'Active Downloads',
                    tasks: state.activeTasks,
                    isDark: isDark,
                    progressByTaskId: state.currentProgress,
                    onPause: _controller.pauseDownload,
                    onResume: _controller.resumeDownload,
                    onCancel: _controller.cancelDownload,
                    onRetry: _controller.retryDownload,
                  ),
                  DownloadQueueSection(
                    title: 'Pending',
                    tasks: state.pendingTasks,
                    isDark: isDark,
                    progressByTaskId: state.currentProgress,
                    onPause: _controller.pauseDownload,
                    onResume: _controller.resumeDownload,
                    onCancel: _controller.cancelDownload,
                    onRetry: _controller.retryDownload,
                  ),
                  DownloadedSection(
                    completedTasks: state.completedTasks,
                    sortedAlbumKeys: state.sortedCompletedAlbumKeys,
                    groupedByAlbum: state.groupedCompletedTasks,
                    expandedAlbums: state.expandedAlbums,
                    isDark: isDark,
                    onToggleAlbum: _controller.toggleAlbumExpanded,
                    onDeleteAlbumGroup: (albumId, name, count) =>
                        _confirmDeleteAlbum(albumId, name, count),
                    onRemoveSong: _controller.cancelDownload,
                  ),
                  DownloadQueueSection(
                    title: 'Failed',
                    tasks: state.failedTasks,
                    isDark: isDark,
                    progressByTaskId: state.currentProgress,
                    onPause: _controller.pauseDownload,
                    onResume: _controller.resumeDownload,
                    onCancel: _controller.cancelDownload,
                    onRetry: _controller.retryDownload,
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
