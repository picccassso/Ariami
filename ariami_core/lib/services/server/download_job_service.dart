import 'dart:collection';
import 'dart:math';

import 'package:ariami_core/models/download_job_models.dart';
import 'package:ariami_core/models/folder_playlist.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:ariami_core/services/library/library_manager.dart';

typedef DownloadJobCatalogRepositoryProvider = CatalogRepository? Function();

class DownloadJobServiceException implements Exception {
  const DownloadJobServiceException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
    this.retryAfterSeconds,
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? retryAfterSeconds;
}

/// Server-managed orchestration for large download requests.
class DownloadJobService {
  DownloadJobService({
    required DownloadJobCatalogRepositoryProvider catalogRepositoryProvider,
    required LibraryManager libraryManager,
    int maxActiveJobsPerUser = _defaultMaxActiveJobsPerUser,
    int maxQueuedItemsPerUser = _defaultMaxQueuedItemsPerUser,
  })  : _catalogRepositoryProvider = catalogRepositoryProvider,
        _libraryManager = libraryManager,
        _maxActiveJobsPerUser = maxActiveJobsPerUser,
        _maxQueuedItemsPerUser = maxQueuedItemsPerUser;

  final DownloadJobCatalogRepositoryProvider _catalogRepositoryProvider;
  final LibraryManager _libraryManager;
  final Random _random = Random.secure();
  final Map<String, _DownloadJobRecord> _jobs = <String, _DownloadJobRecord>{};

  static const int defaultPageLimit = 100;
  static const int maxPageLimit = 500;
  static const int _defaultMaxActiveJobsPerUser = 8;
  static const int _defaultMaxQueuedItemsPerUser = 10000;
  static const int _quotaRetryAfterSeconds = 5;
  static const Set<String> _supportedQualities = <String>{
    'high',
    'medium',
    'low',
  };
  final int _maxActiveJobsPerUser;
  final int _maxQueuedItemsPerUser;

  DownloadJobCreateResponse createJob({
    required String userScopeId,
    required DownloadJobCreateRequest request,
  }) {
    final repository = _catalogRepositoryProvider();
    if (repository == null) {
      throw const DownloadJobServiceException(
        statusCode: 503,
        code: DownloadJobErrorCodes.catalogUnavailable,
        message: 'Catalog database is not initialized',
      );
    }

    final normalizedSongIds = _normalizeIds(request.songIds);
    final normalizedAlbumIds = _normalizeIds(request.albumIds);
    final normalizedPlaylistIds = _normalizeIds(request.playlistIds);

    if (normalizedSongIds.isEmpty &&
        normalizedAlbumIds.isEmpty &&
        normalizedPlaylistIds.isEmpty) {
      throw const DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidRequest,
        message:
            'At least one of songIds, albumIds, or playlistIds is required',
      );
    }

    final quality = request.quality.trim().toLowerCase();
    if (!_supportedQualities.contains(quality)) {
      throw DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidRequest,
        message: 'quality must be one of high, medium, low',
        details: <String, dynamic>{'quality': request.quality},
      );
    }

    final snapshot = _buildCatalogSnapshot(repository);
    final playlistsById = _buildFolderPlaylistsById();

    final invalidSongIds = normalizedSongIds
        .where((songId) => !snapshot.songsById.containsKey(songId))
        .toList();
    final invalidAlbumIds = normalizedAlbumIds
        .where((albumId) => !snapshot.albumsById.containsKey(albumId))
        .toList();
    final invalidPlaylistIds = normalizedPlaylistIds
        .where((playlistId) => !playlistsById.containsKey(playlistId))
        .toList();

    if (invalidSongIds.isNotEmpty ||
        invalidAlbumIds.isNotEmpty ||
        invalidPlaylistIds.isNotEmpty) {
      throw DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidRequest,
        message: 'Some requested IDs are invalid',
        details: <String, dynamic>{
          if (invalidSongIds.isNotEmpty) 'invalidSongIds': invalidSongIds,
          if (invalidAlbumIds.isNotEmpty) 'invalidAlbumIds': invalidAlbumIds,
          if (invalidPlaylistIds.isNotEmpty)
            'invalidPlaylistIds': invalidPlaylistIds,
        },
      );
    }

    final resolvedSongIds = LinkedHashSet<String>();
    resolvedSongIds.addAll(normalizedSongIds);

    for (final albumId in normalizedAlbumIds) {
      final albumSongs = snapshot.songsByAlbumId[albumId];
      if (albumSongs == null) continue;
      for (final song in albumSongs) {
        resolvedSongIds.add(song.id);
      }
    }

    for (final playlistId in normalizedPlaylistIds) {
      final playlist = playlistsById[playlistId];
      if (playlist == null) continue;
      for (final songId in playlist.songIds) {
        if (snapshot.songsById.containsKey(songId)) {
          resolvedSongIds.add(songId);
        }
      }
    }

    if (resolvedSongIds.isEmpty) {
      throw const DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidRequest,
        message: 'No valid songs resolved from requested IDs',
      );
    }

    _enforcePerUserQuotas(
      userScopeId: userScopeId,
      additionalQueuedItems: resolvedSongIds.length,
    );

    final now = DateTime.now().toUtc();
    final jobId = _generateJobId(now);

    final items = <_DownloadJobItemRecord>[];
    var itemOrder = 0;
    for (final songId in resolvedSongIds) {
      final song = snapshot.songsById[songId]!;
      final album =
          song.albumId != null ? snapshot.albumsById[song.albumId!] : null;
      items.add(
        _DownloadJobItemRecord(
          itemOrder: itemOrder,
          songId: song.id,
          status: DownloadJobItemStatus.pending,
          title: song.title,
          artist: song.artist,
          albumId: song.albumId,
          albumName: album?.title,
          albumArtist: album?.artist,
          trackNumber: song.trackNumber,
          durationSeconds: song.durationSeconds,
          fileSizeBytes: song.fileSizeBytes,
        ),
      );
      itemOrder += 1;
    }

    final record = _DownloadJobRecord(
      jobId: jobId,
      userScopeId: userScopeId,
      status: DownloadJobStatus.ready,
      quality: quality,
      downloadOriginal: request.downloadOriginal,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
    _jobs[jobId] = record;

    return DownloadJobCreateResponse(
      jobId: record.jobId,
      status: record.status,
      quality: record.quality,
      downloadOriginal: record.downloadOriginal,
      itemCount: record.items.length,
      createdAt: record.createdAt.toIso8601String(),
      updatedAt: record.updatedAt.toIso8601String(),
    );
  }

  DownloadJobStatusResponse getJob({
    required String userScopeId,
    required String jobId,
  }) {
    final record = _requireScopedJob(userScopeId: userScopeId, jobId: jobId);
    return record.toStatusResponse();
  }

  DownloadJobItemsResponse getJobItems({
    required String userScopeId,
    required String jobId,
    int? cursor,
    int limit = defaultPageLimit,
  }) {
    if (limit <= 0 || limit > maxPageLimit) {
      throw const DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidRequest,
        message: 'limit must be between 1 and 500',
      );
    }
    if (cursor != null && cursor < 0) {
      throw const DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidCursor,
        message: 'cursor must be a non-negative integer',
      );
    }

    final record = _requireScopedJob(userScopeId: userScopeId, jobId: jobId);
    final startAfter = cursor ?? -1;
    final pageItems = record.items
        .where((item) => item.itemOrder > startAfter)
        .take(limit)
        .map((item) => item.toResponse())
        .toList();

    final hasMore = pageItems.isNotEmpty
        ? record.items.last.itemOrder > pageItems.last.itemOrder
        : false;
    final nextCursor =
        hasMore && pageItems.isNotEmpty ? '${pageItems.last.itemOrder}' : null;

    return DownloadJobItemsResponse(
      jobId: record.jobId,
      items: pageItems,
      pageInfo: DownloadJobPageInfo(
        cursor: cursor != null ? '$cursor' : null,
        nextCursor: nextCursor,
        hasMore: hasMore,
        limit: limit,
      ),
    );
  }

  DownloadJobCancelResponse cancelJob({
    required String userScopeId,
    required String jobId,
  }) {
    final record = _requireScopedJob(userScopeId: userScopeId, jobId: jobId);
    if (record.status == DownloadJobStatus.cancelled) {
      return DownloadJobCancelResponse(
        jobId: record.jobId,
        status: record.status,
        cancelledAt: record.updatedAt.toIso8601String(),
      );
    }

    final now = DateTime.now().toUtc();
    record.status = DownloadJobStatus.cancelled;
    record.updatedAt = now;
    for (final item in record.items) {
      if (item.status == DownloadJobItemStatus.pending) {
        item.status = DownloadJobItemStatus.cancelled;
      }
    }

    return DownloadJobCancelResponse(
      jobId: record.jobId,
      status: record.status,
      cancelledAt: now.toIso8601String(),
    );
  }

  _DownloadJobRecord _requireScopedJob({
    required String userScopeId,
    required String jobId,
  }) {
    final record = _jobs[jobId];
    if (record == null || record.userScopeId != userScopeId) {
      throw const DownloadJobServiceException(
        statusCode: 404,
        code: DownloadJobErrorCodes.jobNotFound,
        message: 'Download job not found',
      );
    }
    return record;
  }

  String _generateJobId(DateTime now) {
    final nonce = _random
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toLowerCase();
    return 'dj_${now.millisecondsSinceEpoch}_$nonce';
  }

  List<String> _normalizeIds(List<String> ids) {
    final deduped = LinkedHashSet<String>();
    for (final id in ids) {
      final trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      deduped.add(trimmed);
    }
    return deduped.toList();
  }

  _CatalogSnapshot _buildCatalogSnapshot(CatalogRepository repository) {
    final songsById = <String, _CatalogSongView>{};
    final songsByAlbumId = <String, List<_CatalogSongView>>{};
    final albumsById = <String, _CatalogAlbumView>{};

    String? songCursor;
    while (true) {
      final page = repository.listSongsPage(cursor: songCursor, limit: 500);
      for (final song in page.items) {
        final view = _CatalogSongView(
          id: song.id,
          title: song.title,
          artist: song.artist,
          albumId: song.albumId,
          durationSeconds: song.durationSeconds,
          trackNumber: song.trackNumber,
          fileSizeBytes: song.fileSizeBytes,
        );
        songsById[view.id] = view;
        final albumId = view.albumId;
        if (albumId != null) {
          songsByAlbumId.putIfAbsent(albumId, () => <_CatalogSongView>[]).add(
                view,
              );
        }
      }
      if (!page.hasMore || page.nextCursor == null) {
        break;
      }
      songCursor = page.nextCursor;
    }

    for (final songs in songsByAlbumId.values) {
      songs.sort((a, b) {
        final trackCompare =
            (a.trackNumber ?? 1 << 30).compareTo(b.trackNumber ?? 1 << 30);
        if (trackCompare != 0) return trackCompare;
        return a.id.compareTo(b.id);
      });
    }

    String? albumCursor;
    while (true) {
      final page = repository.listAlbumsPage(cursor: albumCursor, limit: 500);
      for (final album in page.items) {
        albumsById[album.id] = _CatalogAlbumView(
          id: album.id,
          title: album.title,
          artist: album.artist,
        );
      }
      if (!page.hasMore || page.nextCursor == null) {
        break;
      }
      albumCursor = page.nextCursor;
    }

    return _CatalogSnapshot(
      songsById: songsById,
      songsByAlbumId: songsByAlbumId,
      albumsById: albumsById,
    );
  }

  Map<String, FolderPlaylist> _buildFolderPlaylistsById() {
    final library = _libraryManager.library;
    if (library == null) {
      return <String, FolderPlaylist>{};
    }

    return <String, FolderPlaylist>{
      for (final playlist in library.folderPlaylists) playlist.id: playlist,
    };
  }

  void _enforcePerUserQuotas({
    required String userScopeId,
    required int additionalQueuedItems,
  }) {
    var activeJobs = 0;
    var queuedItems = 0;

    for (final job in _jobs.values) {
      if (job.userScopeId != userScopeId) continue;
      if (job.status != DownloadJobStatus.ready) continue;

      activeJobs += 1;
      queuedItems += job.items
          .where((item) => item.status == DownloadJobItemStatus.pending)
          .length;
    }

    if (activeJobs >= _maxActiveJobsPerUser) {
      throw DownloadJobServiceException(
        statusCode: 429,
        code: 'QUOTA_EXCEEDED',
        message: 'Too many active download jobs for user',
        retryAfterSeconds: _quotaRetryAfterSeconds,
        details: <String, dynamic>{
          'maxActiveJobsPerUser': _maxActiveJobsPerUser,
        },
      );
    }

    final projectedQueuedItems = queuedItems + additionalQueuedItems;
    if (projectedQueuedItems > _maxQueuedItemsPerUser) {
      throw DownloadJobServiceException(
        statusCode: 429,
        code: 'QUOTA_EXCEEDED',
        message: 'Per-user queued downloads quota exceeded',
        retryAfterSeconds: _quotaRetryAfterSeconds,
        details: <String, dynamic>{
          'maxQueuedItemsPerUser': _maxQueuedItemsPerUser,
          'queuedItems': queuedItems,
          'requestedItems': additionalQueuedItems,
        },
      );
    }
  }
}

class _CatalogSnapshot {
  _CatalogSnapshot({
    required this.songsById,
    required this.songsByAlbumId,
    required this.albumsById,
  });

  final Map<String, _CatalogSongView> songsById;
  final Map<String, List<_CatalogSongView>> songsByAlbumId;
  final Map<String, _CatalogAlbumView> albumsById;
}

class _CatalogSongView {
  _CatalogSongView({
    required this.id,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.durationSeconds,
    required this.trackNumber,
    required this.fileSizeBytes,
  });

  final String id;
  final String title;
  final String artist;
  final String? albumId;
  final int durationSeconds;
  final int? trackNumber;
  final int? fileSizeBytes;
}

class _CatalogAlbumView {
  _CatalogAlbumView({
    required this.id,
    required this.title,
    required this.artist,
  });

  final String id;
  final String title;
  final String artist;
}

class _DownloadJobRecord {
  _DownloadJobRecord({
    required this.jobId,
    required this.userScopeId,
    required this.status,
    required this.quality,
    required this.downloadOriginal,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  final String jobId;
  final String userScopeId;
  String status;
  final String quality;
  final bool downloadOriginal;
  final List<_DownloadJobItemRecord> items;
  final DateTime createdAt;
  DateTime updatedAt;

  DownloadJobStatusResponse toStatusResponse() {
    final pendingCount = items
        .where((item) => item.status == DownloadJobItemStatus.pending)
        .length;
    final cancelledCount = items
        .where((item) => item.status == DownloadJobItemStatus.cancelled)
        .length;

    return DownloadJobStatusResponse(
      jobId: jobId,
      userId: userScopeId,
      status: status,
      quality: quality,
      downloadOriginal: downloadOriginal,
      itemCount: items.length,
      pendingCount: pendingCount,
      cancelledCount: cancelledCount,
      createdAt: createdAt.toIso8601String(),
      updatedAt: updatedAt.toIso8601String(),
    );
  }
}

class _DownloadJobItemRecord {
  _DownloadJobItemRecord({
    required this.itemOrder,
    required this.songId,
    required this.status,
    required this.title,
    required this.artist,
    this.albumId,
    this.albumName,
    this.albumArtist,
    this.trackNumber,
    required this.durationSeconds,
    this.fileSizeBytes,
  });

  final int itemOrder;
  final String songId;
  String status;
  final String title;
  final String artist;
  final String? albumId;
  final String? albumName;
  final String? albumArtist;
  final int? trackNumber;
  final int durationSeconds;
  final int? fileSizeBytes;

  DownloadJobItemResponse toResponse() {
    return DownloadJobItemResponse(
      itemOrder: itemOrder,
      songId: songId,
      status: status,
      title: title,
      artist: artist,
      albumId: albumId,
      albumName: albumName,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      errorCode: null,
      retryAfterEpochMs: null,
    );
  }
}
