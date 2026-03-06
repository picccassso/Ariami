/// Models for v2 server-managed download jobs.
library;

class DownloadJobCreateRequest {
  const DownloadJobCreateRequest({
    this.songIds = const <String>[],
    this.albumIds = const <String>[],
    this.playlistIds = const <String>[],
    this.quality = 'high',
    this.downloadOriginal = false,
  });

  final List<String> songIds;
  final List<String> albumIds;
  final List<String> playlistIds;
  final String quality;
  final bool downloadOriginal;

  bool get hasTargets =>
      songIds.isNotEmpty || albumIds.isNotEmpty || playlistIds.isNotEmpty;

  factory DownloadJobCreateRequest.fromJson(Map<String, dynamic> json) {
    List<String> parseIds(dynamic value) {
      if (value is! List) return const <String>[];
      return value
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList();
    }

    return DownloadJobCreateRequest(
      songIds: parseIds(json['songIds']),
      albumIds: parseIds(json['albumIds']),
      playlistIds: parseIds(json['playlistIds']),
      quality: (json['quality'] as String? ?? 'high').trim().toLowerCase(),
      downloadOriginal: json['downloadOriginal'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'songIds': songIds,
      'albumIds': albumIds,
      'playlistIds': playlistIds,
      'quality': quality,
      'downloadOriginal': downloadOriginal,
    };
  }
}

class DownloadJobPageInfo {
  const DownloadJobPageInfo({
    required this.cursor,
    required this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  final String? cursor;
  final String? nextCursor;
  final bool hasMore;
  final int limit;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'cursor': cursor,
      'nextCursor': nextCursor,
      'hasMore': hasMore,
      'limit': limit,
    };
  }
}

class DownloadJobCreateResponse {
  const DownloadJobCreateResponse({
    required this.jobId,
    required this.status,
    required this.quality,
    required this.downloadOriginal,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String jobId;
  final String status;
  final String quality;
  final bool downloadOriginal;
  final int itemCount;
  final String createdAt;
  final String updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'jobId': jobId,
      'status': status,
      'quality': quality,
      'downloadOriginal': downloadOriginal,
      'itemCount': itemCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class DownloadJobStatusResponse {
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'jobId': jobId,
      'userId': userId,
      'status': status,
      'quality': quality,
      'downloadOriginal': downloadOriginal,
      'itemCount': itemCount,
      'pendingCount': pendingCount,
      'cancelledCount': cancelledCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class DownloadJobItemResponse {
  const DownloadJobItemResponse({
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'itemOrder': itemOrder,
      'songId': songId,
      'status': status,
      'title': title,
      'artist': artist,
      'albumId': albumId,
      'albumName': albumName,
      'albumArtist': albumArtist,
      'trackNumber': trackNumber,
      'durationSeconds': durationSeconds,
      'fileSizeBytes': fileSizeBytes,
      'errorCode': errorCode,
      'retryAfterEpochMs': retryAfterEpochMs,
    };
  }
}

class DownloadJobItemsResponse {
  const DownloadJobItemsResponse({
    required this.jobId,
    required this.items,
    required this.pageInfo,
  });

  final String jobId;
  final List<DownloadJobItemResponse> items;
  final DownloadJobPageInfo pageInfo;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'jobId': jobId,
      'items': items.map((item) => item.toJson()).toList(),
      'pageInfo': pageInfo.toJson(),
    };
  }
}

class DownloadJobCancelResponse {
  const DownloadJobCancelResponse({
    required this.jobId,
    required this.status,
    required this.cancelledAt,
  });

  final String jobId;
  final String status;
  final String cancelledAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'jobId': jobId,
      'status': status,
      'cancelledAt': cancelledAt,
    };
  }
}

class DownloadJobStatus {
  static const String ready = 'ready';
  static const String cancelled = 'cancelled';
}

class DownloadJobItemStatus {
  static const String pending = 'pending';
  static const String cancelled = 'cancelled';
}

class DownloadJobErrorCodes {
  static const String invalidRequest = 'INVALID_REQUEST';
  static const String catalogUnavailable = 'CATALOG_UNAVAILABLE';
  static const String jobNotFound = 'JOB_NOT_FOUND';
  static const String invalidCursor = 'INVALID_CURSOR';
}
