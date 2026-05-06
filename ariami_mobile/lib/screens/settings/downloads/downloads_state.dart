import 'package:flutter/foundation.dart';

import '../../../models/download_task.dart';
import '../../../models/quality_settings.dart';

/// Live progress snapshot for a single album-grouped section row. Updated at
/// the throttled flush cadence so collapsed rows can show "60%" without
/// rebuilding the whole screen on every byte tick.
@immutable
class AlbumProgressSnapshot {
  const AlbumProgressSnapshot({
    required this.bytesDone,
    required this.bytesTotal,
  });

  final int bytesDone;
  final int bytesTotal;

  static const empty = AlbumProgressSnapshot(bytesDone: 0, bytesTotal: 0);

  double get progress => bytesTotal > 0 ? bytesDone / bytesTotal : 0.0;
  int get percentage => (progress * 100).clamp(0, 100).toInt();
}

/// Whole-screen progress aggregate for the summary card. Like
/// [AlbumProgressSnapshot] this is updated at the throttled flush cadence.
@immutable
class OverallProgressSummary {
  const OverallProgressSummary({
    this.totalSongs = 0,
    this.completedSongs = 0,
    this.inProgressSongs = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
  });

  final int totalSongs;
  final int completedSongs;
  final int inProgressSongs;
  final int bytesDone;
  final int bytesTotal;

  static const empty = OverallProgressSummary();

  bool get hasActivity => inProgressSongs > 0;
  double get progress => totalSongs > 0 ? completedSongs / totalSongs : 0.0;
  int get percentage => (progress * 100).clamp(0, 100).toInt();
}

/// A grouping of [DownloadTask]s sharing the same album, used by the In
/// Progress and Failed sections. Structural (changes only on status
/// transitions / queue add-remove); live byte progress is delivered
/// separately via per-album [AlbumProgressSnapshot] notifiers.
@immutable
class AlbumGroup {
  const AlbumGroup({
    required this.albumId,
    required this.albumName,
    required this.albumArtist,
    required this.albumArt,
    required this.songs,
    required this.downloadingCount,
    required this.pausedCount,
    required this.queuedCount,
    required this.failedCount,
    required this.orderHint,
  });

  /// `null` for songs without an album (singles).
  final String? albumId;
  final String albumName;
  final String albumArtist;
  final String albumArt;
  final List<DownloadTask> songs;
  final int downloadingCount;
  final int pausedCount;
  final int queuedCount;
  final int failedCount;
  final int orderHint;

  /// Stable identifier for expansion-set membership and notifier maps.
  String get key => albumId ?? '__singles__';

  int get totalCount => songs.length;
}

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
    this.inProgressAlbums = const <AlbumGroup>[],
    this.failedAlbums = const <AlbumGroup>[],
    this.completedTasks = const <DownloadTask>[],
    this.groupedCompletedTasks = const <String?, List<DownloadTask>>{},
    this.sortedCompletedAlbumKeys = const <String?>[],
    this.expandedAlbums = const <String>{},
    this.hasAnyInProgress = false,
    this.hasAnyFailed = false,
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

  final List<AlbumGroup> inProgressAlbums;
  final List<AlbumGroup> failedAlbums;
  final List<DownloadTask> completedTasks;
  final Map<String?, List<DownloadTask>> groupedCompletedTasks;
  final List<String?> sortedCompletedAlbumKeys;

  final Set<String> expandedAlbums;
  final bool hasAnyInProgress;
  final bool hasAnyFailed;

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
    List<AlbumGroup>? inProgressAlbums,
    List<AlbumGroup>? failedAlbums,
    List<DownloadTask>? completedTasks,
    Map<String?, List<DownloadTask>>? groupedCompletedTasks,
    List<String?>? sortedCompletedAlbumKeys,
    Set<String>? expandedAlbums,
    bool? hasAnyInProgress,
    bool? hasAnyFailed,
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
      inProgressAlbums: inProgressAlbums ?? this.inProgressAlbums,
      failedAlbums: failedAlbums ?? this.failedAlbums,
      completedTasks: completedTasks ?? this.completedTasks,
      groupedCompletedTasks:
          groupedCompletedTasks ?? this.groupedCompletedTasks,
      sortedCompletedAlbumKeys:
          sortedCompletedAlbumKeys ?? this.sortedCompletedAlbumKeys,
      expandedAlbums: expandedAlbums ?? this.expandedAlbums,
      hasAnyInProgress: hasAnyInProgress ?? this.hasAnyInProgress,
      hasAnyFailed: hasAnyFailed ?? this.hasAnyFailed,
    );
  }
}
