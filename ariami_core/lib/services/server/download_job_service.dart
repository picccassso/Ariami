import 'dart:collection';
import 'dart:math';

import 'package:ariami_core/models/download_job_models.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';

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
    int maxActiveJobsPerUser = _defaultMaxActiveJobsPerUser,
    int maxQueuedItemsPerUser = _defaultMaxQueuedItemsPerUser,
    int maxTotalJobs = _defaultMaxTotalJobs,
    Duration cancelledJobRetention = _defaultCancelledJobRetention,
    DateTime Function()? nowProvider,
  })  : _catalogRepositoryProvider = catalogRepositoryProvider,
        _maxActiveJobsPerUser = maxActiveJobsPerUser,
        _maxQueuedItemsPerUser = maxQueuedItemsPerUser,
        _maxTotalJobs = maxTotalJobs,
        _cancelledJobRetention = cancelledJobRetention,
        _nowProvider = nowProvider ?? (() => DateTime.now().toUtc());

  final DownloadJobCatalogRepositoryProvider _catalogRepositoryProvider;
  final Random _random = Random.secure();
  final Map<String, _DownloadJobRecord> _jobs = <String, _DownloadJobRecord>{};

  static const int defaultPageLimit = 100;
  static const int maxPageLimit = 500;
  static const int _defaultMaxActiveJobsPerUser = 8;
  static const int _defaultMaxQueuedItemsPerUser = 10000;
  static const int _quotaRetryAfterSeconds = 5;
  static const int _defaultMaxTotalJobs = 1000;
  static const Duration _defaultCancelledJobRetention = Duration(hours: 1);
  static const Set<String> _supportedQualities = <String>{
    'high',
    'medium',
    'low',
  };
  final int _maxActiveJobsPerUser;
  final int _maxQueuedItemsPerUser;
  final int _maxTotalJobs;
  final Duration _cancelledJobRetention;
  final DateTime Function() _nowProvider;

  DownloadJobCreateResponse createJob({
    required String userScopeId,
    required DownloadJobCreateRequest request,
  }) {
    _opportunisticCleanup();

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

    final songRecords = repository.getSongsByIds(normalizedSongIds);
    final songsById = {for (final s in songRecords) s.id: s};

    final albumRecords = repository.getAlbumsByIds(normalizedAlbumIds);
    final albumsById = {for (final a in albumRecords) a.id: a};

    final playlistRecords = repository.getPlaylistsByIds(normalizedPlaylistIds);
    final playlistsById = {for (final p in playlistRecords) p.id: p};

    final invalidSongIds = normalizedSongIds
        .where((songId) => !songsById.containsKey(songId))
        .toList();
    final invalidAlbumIds = normalizedAlbumIds
        .where((albumId) => !albumsById.containsKey(albumId))
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

    final albumSongs = repository.getSongsByAlbumIds(normalizedAlbumIds);
    final songsByAlbumId = <String, List<CatalogSongRecord>>{};
    for (final song in albumSongs) {
      if (song.albumId != null) {
        songsByAlbumId.putIfAbsent(song.albumId!, () => []).add(song);
      }
    }
    for (final songs in songsByAlbumId.values) {
      songs.sort((a, b) {
        final trackCompare =
            (a.trackNumber ?? 1 << 30).compareTo(b.trackNumber ?? 1 << 30);
        if (trackCompare != 0) return trackCompare;
        return a.id.compareTo(b.id);
      });
    }

    for (final albumId in normalizedAlbumIds) {
      final songs = songsByAlbumId[albumId];
      if (songs == null) continue;
      for (final song in songs) {
        resolvedSongIds.add(song.id);
      }
    }

    final playlistSongs =
        repository.getPlaylistSongsByPlaylistIds(normalizedPlaylistIds);
    final playlistSongIdsByPlaylistId = <String, List<String>>{};
    for (final ps in playlistSongs) {
      playlistSongIdsByPlaylistId
          .putIfAbsent(ps.playlistId, () => [])
          .add(ps.songId);
    }

    for (final playlistId in normalizedPlaylistIds) {
      final pSongs = playlistSongIdsByPlaylistId[playlistId];
      if (pSongs == null) continue;
      for (final songId in pSongs) {
        // We do not strict validate playlist songs existence here,
        // we filter them later when fetching the final list
        resolvedSongIds.add(songId);
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

    final now = _nowProvider();
    final jobId = _generateJobId(now);

    final allResolvedSongs = repository.getSongsByIds(resolvedSongIds.toList());
    final allResolvedSongsById = {for (final s in allResolvedSongs) s.id: s};
    final resolvedAlbumIdsToFetch =
        allResolvedSongs.map((s) => s.albumId).whereType<String>().toSet();
    final resolvedAlbums =
        repository.getAlbumsByIds(resolvedAlbumIdsToFetch.toList());
    final allResolvedAlbumsById = {for (final a in resolvedAlbums) a.id: a};

    final items = <_DownloadJobItemRecord>[];
    var itemOrder = 0;
    for (final songId in resolvedSongIds) {
      final song = allResolvedSongsById[songId];
      if (song == null) continue; // Skip invalid/deleted playlist songs
      final album =
          song.albumId != null ? allResolvedAlbumsById[song.albumId!] : null;
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

    // Check again if empty after skipping missing playlist songs
    if (items.isEmpty) {
      throw const DownloadJobServiceException(
        statusCode: 400,
        code: DownloadJobErrorCodes.invalidRequest,
        message: 'No valid songs resolved from requested IDs',
      );
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
    _opportunisticCleanup();

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
    _opportunisticCleanup();

    final record = _requireScopedJob(userScopeId: userScopeId, jobId: jobId);
    return record.toStatusResponse();
  }

  DownloadJobItemsResponse getJobItems({
    required String userScopeId,
    required String jobId,
    int? cursor,
    int limit = defaultPageLimit,
  }) {
    _opportunisticCleanup();

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

    final now = _nowProvider();
    record.status = DownloadJobStatus.cancelled;
    record.updatedAt = now;
    for (final item in record.items) {
      if (item.status == DownloadJobItemStatus.pending) {
        item.status = DownloadJobItemStatus.cancelled;
      }
    }

    _opportunisticCleanup();

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

  void _opportunisticCleanup() {
    if (_jobs.isEmpty) return;

    final now = _nowProvider();
    final expiredDate = now.subtract(_cancelledJobRetention);

    // First, remove old cancelled jobs
    _jobs.removeWhere((id, job) =>
        job.status == DownloadJobStatus.cancelled &&
        job.updatedAt.isBefore(expiredDate));

    // Backstop: If we still have too many jobs, remove the oldest ones
    if (_jobs.length > _maxTotalJobs) {
      final sortedJobs = _jobs.values.toList()
        ..sort((a, b) {
          // Prioritize removing cancelled jobs over ready ones
          if (a.status != b.status) {
            if (a.status == DownloadJobStatus.cancelled) return -1;
            if (b.status == DownloadJobStatus.cancelled) return 1;
          }
          return a.createdAt.compareTo(b.createdAt);
        });

      final jobsToRemove = sortedJobs.take(_jobs.length - _maxTotalJobs);
      for (final job in jobsToRemove) {
        _jobs.remove(job.jobId);
      }
    }
  }
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
