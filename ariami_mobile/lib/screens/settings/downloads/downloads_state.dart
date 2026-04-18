import 'package:flutter/foundation.dart';

import '../../../models/download_task.dart';
import '../../../models/quality_settings.dart';
import '../../../services/download/download_manager.dart';

/// Immutable state for the downloads screen UI.
@immutable
class DownloadsState {
  const DownloadsState({
    this.cacheSizeMB = 0,
    this.cachedSongCount = 0,
    this.cacheLimitMB = 500,
    this.totalSongCount = 0,
    this.totalAlbumCount = 0,
    this.downloadedSongCount = 0,
    this.downloadedAlbumCount = 0,
    this.downloadedPlaylistSongCount = 0,
    this.totalPlaylistSongCount = 0,
    this.isLoadingCounts = true,
    this.isDownloadingAllSongs = false,
    this.isDownloadingAllAlbums = false,
    this.isDownloadingAllPlaylists = false,
    this.downloadQuality = StreamingQuality.high,
    this.downloadOriginal = false,
    this.autoResumeInterruptedOnLaunch = false,
    this.interruptedDownloadCount = 0,
    this.activeTasks = const <DownloadTask>[],
    this.pendingTasks = const <DownloadTask>[],
    this.completedTasks = const <DownloadTask>[],
    this.failedTasks = const <DownloadTask>[],
    this.groupedCompletedTasks = const <String?, List<DownloadTask>>{},
    this.sortedCompletedAlbumKeys = const <String?>[],
    this.currentProgress = const <String, DownloadProgress>{},
    this.expandedAlbums = const <String>{},
  });

  final double cacheSizeMB;
  final int cachedSongCount;
  final int cacheLimitMB;

  final int totalSongCount;
  final int totalAlbumCount;
  final int downloadedSongCount;
  final int downloadedAlbumCount;
  final int downloadedPlaylistSongCount;
  final int totalPlaylistSongCount;

  final bool isLoadingCounts;
  final bool isDownloadingAllSongs;
  final bool isDownloadingAllAlbums;
  final bool isDownloadingAllPlaylists;
  final StreamingQuality downloadQuality;
  final bool downloadOriginal;
  final bool autoResumeInterruptedOnLaunch;
  final int interruptedDownloadCount;

  final List<DownloadTask> activeTasks;
  final List<DownloadTask> pendingTasks;
  final List<DownloadTask> completedTasks;
  final List<DownloadTask> failedTasks;
  final Map<String?, List<DownloadTask>> groupedCompletedTasks;
  final List<String?> sortedCompletedAlbumKeys;

  final Map<String, DownloadProgress> currentProgress;
  final Set<String> expandedAlbums;

  DownloadsState copyWith({
    double? cacheSizeMB,
    int? cachedSongCount,
    int? cacheLimitMB,
    int? totalSongCount,
    int? totalAlbumCount,
    int? downloadedSongCount,
    int? downloadedAlbumCount,
    int? downloadedPlaylistSongCount,
    int? totalPlaylistSongCount,
    bool? isLoadingCounts,
    bool? isDownloadingAllSongs,
    bool? isDownloadingAllAlbums,
    bool? isDownloadingAllPlaylists,
    StreamingQuality? downloadQuality,
    bool? downloadOriginal,
    bool? autoResumeInterruptedOnLaunch,
    int? interruptedDownloadCount,
    List<DownloadTask>? activeTasks,
    List<DownloadTask>? pendingTasks,
    List<DownloadTask>? completedTasks,
    List<DownloadTask>? failedTasks,
    Map<String?, List<DownloadTask>>? groupedCompletedTasks,
    List<String?>? sortedCompletedAlbumKeys,
    Map<String, DownloadProgress>? currentProgress,
    Set<String>? expandedAlbums,
  }) {
    return DownloadsState(
      cacheSizeMB: cacheSizeMB ?? this.cacheSizeMB,
      cachedSongCount: cachedSongCount ?? this.cachedSongCount,
      cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
      totalSongCount: totalSongCount ?? this.totalSongCount,
      totalAlbumCount: totalAlbumCount ?? this.totalAlbumCount,
      downloadedSongCount: downloadedSongCount ?? this.downloadedSongCount,
      downloadedAlbumCount: downloadedAlbumCount ?? this.downloadedAlbumCount,
      downloadedPlaylistSongCount:
          downloadedPlaylistSongCount ?? this.downloadedPlaylistSongCount,
      totalPlaylistSongCount:
          totalPlaylistSongCount ?? this.totalPlaylistSongCount,
      isLoadingCounts: isLoadingCounts ?? this.isLoadingCounts,
      isDownloadingAllSongs:
          isDownloadingAllSongs ?? this.isDownloadingAllSongs,
      isDownloadingAllAlbums:
          isDownloadingAllAlbums ?? this.isDownloadingAllAlbums,
      isDownloadingAllPlaylists:
          isDownloadingAllPlaylists ?? this.isDownloadingAllPlaylists,
      downloadQuality: downloadQuality ?? this.downloadQuality,
      downloadOriginal: downloadOriginal ?? this.downloadOriginal,
      autoResumeInterruptedOnLaunch:
          autoResumeInterruptedOnLaunch ?? this.autoResumeInterruptedOnLaunch,
      interruptedDownloadCount:
          interruptedDownloadCount ?? this.interruptedDownloadCount,
      activeTasks: activeTasks ?? this.activeTasks,
      pendingTasks: pendingTasks ?? this.pendingTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      failedTasks: failedTasks ?? this.failedTasks,
      groupedCompletedTasks:
          groupedCompletedTasks ?? this.groupedCompletedTasks,
      sortedCompletedAlbumKeys:
          sortedCompletedAlbumKeys ?? this.sortedCompletedAlbumKeys,
      currentProgress: currentProgress ?? this.currentProgress,
      expandedAlbums: expandedAlbums ?? this.expandedAlbums,
    );
  }
}
