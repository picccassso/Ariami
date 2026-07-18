part of '../api_models.dart';

// ============================================================================
// V2 DOWNLOAD JOB MODELS
// ============================================================================

class DownloadJobCreateRequest {
  final List<String> songIds;
  final List<String> albumIds;
  final List<String> playlistIds;
  final String quality;
  final bool downloadOriginal;

  const DownloadJobCreateRequest({
    this.songIds = const <String>[],
    this.albumIds = const <String>[],
    this.playlistIds = const <String>[],
    this.quality = 'high',
    this.downloadOriginal = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'songIds': songIds,
      'albumIds': albumIds,
      'playlistIds': playlistIds,
      'quality': quality,
      'downloadOriginal': downloadOriginal,
    };
  }
}

class DownloadJobCreateResponse {
  final String jobId;
  final String status;
  final String quality;
  final bool downloadOriginal;
  final int itemCount;
  final String createdAt;
  final String updatedAt;

  const DownloadJobCreateResponse({
    required this.jobId,
    required this.status,
    required this.quality,
    required this.downloadOriginal,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DownloadJobCreateResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobCreateResponse(
      jobId: json['jobId'] as String,
      status: json['status'] as String? ?? '',
      quality: json['quality'] as String? ?? 'high',
      downloadOriginal: json['downloadOriginal'] as bool? ?? false,
      itemCount: json['itemCount'] as int? ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class DownloadJobStatusResponse {
  final String jobId;
  final String userId;
  final String status;
  final String quality;
  final bool downloadOriginal;
  final int itemCount;
  final int pendingCount;
  final int cancelledCount;
  final String createdAt;
  final String updatedAt;

  const DownloadJobStatusResponse({
    required this.jobId,
    required this.userId,
    required this.status,
    required this.quality,
    required this.downloadOriginal,
    required this.itemCount,
    required this.pendingCount,
    required this.cancelledCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DownloadJobStatusResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobStatusResponse(
      jobId: json['jobId'] as String,
      userId: json['userId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      quality: json['quality'] as String? ?? 'high',
      downloadOriginal: json['downloadOriginal'] as bool? ?? false,
      itemCount: json['itemCount'] as int? ?? 0,
      pendingCount: json['pendingCount'] as int? ?? 0,
      cancelledCount: json['cancelledCount'] as int? ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class DownloadJobItemModel {
  final int itemOrder;
  final String songId;
  final String status;
  final String title;
  final String artist;
  final String? albumId;
  final String? albumName;
  final String? albumArtist;
  final int? trackNumber;
  final int durationSeconds;
  final int? fileSizeBytes;
  final String? errorCode;
  final int? retryAfterEpochMs;

  const DownloadJobItemModel({
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
    this.errorCode,
    this.retryAfterEpochMs,
  });

  factory DownloadJobItemModel.fromJson(Map<String, dynamic> json) {
    return DownloadJobItemModel(
      itemOrder: json['itemOrder'] as int? ?? 0,
      songId: json['songId'] as String,
      status: json['status'] as String? ?? '',
      title: EncodingUtils.fixEncoding(json['title'] as String? ?? '') ??
          (json['title'] as String? ?? ''),
      artist: EncodingUtils.fixEncoding(json['artist'] as String? ?? '') ??
          (json['artist'] as String? ?? ''),
      albumId: json['albumId'] as String?,
      albumName: EncodingUtils.fixEncoding(json['albumName'] as String?),
      albumArtist: EncodingUtils.fixEncoding(json['albumArtist'] as String?),
      trackNumber: json['trackNumber'] as int?,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      fileSizeBytes: json['fileSizeBytes'] as int?,
      errorCode: json['errorCode'] as String?,
      retryAfterEpochMs: json['retryAfterEpochMs'] as int?,
    );
  }
}

class DownloadJobItemsPageInfo {
  final String? cursor;
  final String? nextCursor;
  final bool hasMore;
  final int limit;

  const DownloadJobItemsPageInfo({
    required this.cursor,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  factory DownloadJobItemsPageInfo.fromJson(Map<String, dynamic> json) {
    return DownloadJobItemsPageInfo(
      cursor: json['cursor'] as String?,
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
      limit: json['limit'] as int? ?? 0,
    );
  }
}

class DownloadJobItemsResponse {
  final String jobId;
  final List<DownloadJobItemModel> items;
  final DownloadJobItemsPageInfo pageInfo;

  const DownloadJobItemsResponse({
    required this.jobId,
    required this.items,
    required this.pageInfo,
  });

  factory DownloadJobItemsResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobItemsResponse(
      jobId: json['jobId'] as String,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => DownloadJobItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageInfo: DownloadJobItemsPageInfo.fromJson(
        (json['pageInfo'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class DownloadJobCancelResponse {
  final String jobId;
  final String status;
  final String cancelledAt;

  const DownloadJobCancelResponse({
    required this.jobId,
    required this.status,
    required this.cancelledAt,
  });

  factory DownloadJobCancelResponse.fromJson(Map<String, dynamic> json) {
    return DownloadJobCancelResponse(
      jobId: json['jobId'] as String,
      status: json['status'] as String? ?? '',
      cancelledAt: json['cancelledAt'] as String? ?? '',
    );
  }
}
