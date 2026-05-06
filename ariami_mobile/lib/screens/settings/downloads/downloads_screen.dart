import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/download_task.dart';
import '../../../models/quality_settings.dart';
import '../../../services/api/connection_service.dart';
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
  final ConnectionService _connectionService = ConnectionService();
  StreamSubscription<bool>? _connectionSubscription;
  bool _wasConnected = false;
  bool _isReconnectPromptVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = DownloadsController();
    _controller.addListener(_onControllerChanged);
    _wasConnected = _connectionService.isConnected;
    _listenForConnectionRecovery();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showSnackBarMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _listenForConnectionRecovery() {
    _connectionSubscription = _connectionService.connectionStateStream.listen(
      (isConnected) {
        final reconnected = !_wasConnected && isConnected;
        _wasConnected = isConnected;
        if (!reconnected || !mounted) {
          return;
        }

        final interruptedCount = _controller.state.interruptedDownloadCount;
        if (interruptedCount <= 0) {
          return;
        }

        unawaited(_showReconnectRecoveryPrompt(interruptedCount));
      },
    );
  }

  Future<void> _showReconnectRecoveryPrompt(int interruptedCount) async {
    if (!mounted || _isReconnectPromptVisible) {
      return;
    }
    _isReconnectPromptVisible = true;
    try {
      final shouldResume = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Connection Restored'),
          content: Text(
            '$interruptedCount interrupted download${interruptedCount == 1 ? '' : 's'} are waiting. Resume now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep Paused'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Resume All'),
            ),
          ],
        ),
      );

      if (!mounted || shouldResume != true) {
        return;
      }
      await _resumeInterruptedDownloads();
    } finally {
      _isReconnectPromptVisible = false;
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

  Future<void> _resumeInterruptedDownloads() async {
    final resumedCount = await _controller.resumeInterruptedDownloads();
    if (!mounted) return;
    if (resumedCount == 0) {
      _showSnackBarMessage('No interrupted downloads to resume.');
      return;
    }
    _showSnackBarMessage(
      'Resuming $resumedCount interrupted download${resumedCount == 1 ? '' : 's'}.',
    );
  }

  Future<void> _cancelInterruptedDownloads() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Remaining Downloads'),
        content: const Text(
          'This will remove all downloads that were paused after connection loss. Already completed songs stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Paused'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Cancel Remaining',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final cancelledCount = await _controller.cancelInterruptedDownloads();
    if (!mounted) return;
    if (cancelledCount == 0) {
      _showSnackBarMessage('No interrupted downloads to cancel.');
      return;
    }
    _showSnackBarMessage(
      'Cancelled $cancelledCount interrupted download${cancelledCount == 1 ? '' : 's'}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dm = _controller.downloadManager;

    final state = _controller.state;
    final bool hasAnythingToDelete = state.downloadedSongCount > 0 ||
        state.completedTasks.isNotEmpty ||
        state.hasAnyInProgress ||
        state.hasAnyFailed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: hasAnythingToDelete
                  ? null
                  : Theme.of(context).disabledColor,
            ),
            onPressed: hasAnythingToDelete ? _clearAllDownloads : null,
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
              final bool hasActiveDownloads = state.hasAnyInProgress;

              return CustomScrollView(
                slivers: [
                  SliverList(
                    delegate: SliverChildListDelegate([
                      DownloadsSummaryCard(
                        isDark: isDark,
                        summary: _controller.overallProgress,
                      ),
                      StatisticsCard(
                        isDark: isDark,
                        sizeMB: dm.getTotalDownloadedSizeMB(),
                        stats: dm.getQueueStats(),
                      ),
                      DownloadModeCard(
                        isDark: isDark,
                        downloadQuality: state.downloadQuality,
                        downloadOriginal: state.downloadOriginal,
                        onChanged:
                            state.downloadQuality == StreamingQuality.high
                                ? (value) async {
                                    await _controller
                                        .setDownloadOriginal(value);
                                  }
                                : null,
                      ),
                      DownloadsRecoveryPreferencesCard(
                        isDark: isDark,
                        autoResumeOnLaunch:
                            state.autoResumeInterruptedOnLaunch,
                        onChanged: (enabled) {
                          unawaited(
                            _controller
                                .setAutoResumeInterruptedOnLaunch(enabled),
                          );
                        },
                      ),
                      if (state.interruptedDownloadCount > 0)
                        DownloadsInterruptionRecoveryCard(
                          isDark: isDark,
                          interruptedDownloadCount:
                              state.interruptedDownloadCount,
                          onResumeAll: () =>
                              unawaited(_resumeInterruptedDownloads()),
                          onCancelAll: () =>
                              unawaited(_cancelInterruptedDownloads()),
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
                        isDownloadingAllAlbums:
                            state.isDownloadingAllAlbums,
                        isDownloadingAllPlaylists:
                            state.isDownloadingAllPlaylists,
                        isDisabled: hasActiveDownloads,
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
                          _controller
                              .setCacheLimitDuringDrag(value.round());
                        },
                        onLimitChangeEnd: (value) {
                          unawaited(
                              _controller.commitCacheLimit(value.round()));
                        },
                        onClearCache: () => unawaited(_clearCache()),
                      ),
                      const SizedBox(height: 8),
                    ]),
                  ),
                  if (state.hasAnyInProgress)
                    _buildSectionHeader('IN PROGRESS', isDark),
                  if (state.hasAnyInProgress)
                    SliverList.builder(
                      itemCount: state.inProgressAlbums.length,
                      itemBuilder: (context, index) {
                        final album = state.inProgressAlbums[index];
                        return InProgressAlbumCard(
                          key: ValueKey('in_progress_${album.key}'),
                          album: album,
                          isDark: isDark,
                          isLast: index == state.inProgressAlbums.length - 1,
                          isExpanded:
                              state.expandedAlbums.contains(album.key),
                          onToggleExpand: () =>
                              _controller.toggleAlbumExpanded(album.key),
                          albumProgress:
                              _controller.albumProgressFor(album.key),
                          taskProgressBuilder: _controller.taskProgressFor,
                          onPause: _controller.pauseDownload,
                          onResume: _controller.resumeDownload,
                          onCancel: _controller.cancelDownload,
                        );
                      },
                    ),
                  if (state.completedTasks.isNotEmpty)
                    _buildSectionHeader('DOWNLOADED', isDark),
                  if (state.completedTasks.isNotEmpty)
                    SliverList.builder(
                      itemCount: state.sortedCompletedAlbumKeys.length,
                      itemBuilder: (context, index) {
                        final albumId =
                            state.sortedCompletedAlbumKeys[index];
                        final songs = state.groupedCompletedTasks[albumId]!;
                        final isLast =
                            index == state.sortedCompletedAlbumKeys.length - 1;
                        if (albumId == null) {
                          return SinglesCard(
                            songs: songs,
                            isDark: isDark,
                            isLast: isLast,
                            isExpanded: state.expandedAlbums
                                .contains(SinglesCard.singlesKey),
                            onToggleExpand: () => _controller
                                .toggleAlbumExpanded(SinglesCard.singlesKey),
                            onDeleteSingles: () => _confirmDeleteAlbum(
                                null, 'Singles', songs.length),
                            onRemoveSong: _controller.cancelDownload,
                          );
                        }
                        return AlbumCard(
                          albumId: albumId,
                          songs: songs,
                          isDark: isDark,
                          isLast: isLast,
                          isExpanded:
                              state.expandedAlbums.contains(albumId),
                          onToggleExpand: () =>
                              _controller.toggleAlbumExpanded(albumId),
                          onDeleteAlbum: () {
                            final name =
                                songs.first.albumName ?? 'Unknown Album';
                            _confirmDeleteAlbum(
                                albumId, name, songs.length);
                          },
                          onRemoveSong: _controller.cancelDownload,
                        );
                      },
                    ),
                  if (state.hasAnyFailed)
                    _buildSectionHeader('FAILED', isDark),
                  if (state.hasAnyFailed)
                    SliverList.builder(
                      itemCount: state.failedAlbums.length,
                      itemBuilder: (context, index) {
                        final album = state.failedAlbums[index];
                        return FailedAlbumCard(
                          key: ValueKey('failed_${album.key}'),
                          album: album,
                          isDark: isDark,
                          isLast: index == state.failedAlbums.length - 1,
                          isExpanded:
                              state.expandedAlbums.contains(album.key),
                          onToggleExpand: () =>
                              _controller.toggleAlbumExpanded(album.key),
                          onRetryAll: () =>
                              _controller.retryAlbum(album.albumId),
                          onRetrySong: _controller.retryDownload,
                          onDismissSong: _controller.cancelDownload,
                        );
                      },
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: getMiniPlayerAwareBottomPadding(context) + 16,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String text, bool isDark) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
