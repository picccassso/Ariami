/// Download task model for tracking song downloads
library;

import '../utils/encoding_utils.dart';

enum DownloadStatus { pending, downloading, paused, completed, failed, cancelled }

class DownloadTask {
  final String id;
  final String songId;
  String? serverId;
  final String title;
  final String artist;
  final String? albumId;
  final String? albumName;
  final String? albumArtist; // The album's artist (not song artist which may include featured artists)
  final String albumArt;
  final String downloadUrl;
  final int duration; // Duration in seconds
  final int? trackNumber;

  DownloadStatus status;
  double progress; // 0.0 to 1.0
  int bytesDownloaded;
  int totalBytes; // Mutable - updated from HTTP response during download
  String? errorMessage;
  int retryCount;

  static const int maxRetries = 3;

  DownloadTask({
    required this.id,
    required this.songId,
    this.serverId,
    required this.title,
    required this.artist,
    this.albumId,
    this.albumName,
    this.albumArtist,
    required this.albumArt,
    required this.downloadUrl,
    this.duration = 0,
    this.trackNumber,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.bytesDownloaded = 0,
    required this.totalBytes,
    this.errorMessage,
    this.retryCount = 0,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'songId': songId,
      'serverId': serverId,
      'title': title,
      'artist': artist,
      'albumId': albumId,
      'albumName': albumName,
      'albumArtist': albumArtist,
      'albumArt': albumArt,
      'downloadUrl': downloadUrl,
      'duration': duration,
      'trackNumber': trackNumber,
      'status': status.toString(),
      'progress': progress,
      'bytesDownloaded': bytesDownloaded,
      'totalBytes': totalBytes,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
    };
  }

  /// Create from JSON
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      songId: json['songId'] as String,
      serverId: json['serverId'] as String?,
      title: EncodingUtils.fixEncoding(json['title'] as String) ?? json['title'] as String,
      artist: EncodingUtils.fixEncoding(json['artist'] as String) ?? json['artist'] as String,
      albumId: json['albumId'] as String?,
      albumName: EncodingUtils.fixEncoding(json['albumName'] as String?),
      albumArtist: EncodingUtils.fixEncoding(json['albumArtist'] as String?),
      albumArt: json['albumArt'] as String,
      downloadUrl: json['downloadUrl'] as String,
      duration: json['duration'] as int? ?? 0,
      trackNumber: json['trackNumber'] as int?,
      status: _parseStatus(json['status'] as String),
      progress: (json['progress'] as num).toDouble(),
      bytesDownloaded: json['bytesDownloaded'] as int,
      totalBytes: json['totalBytes'] as int,
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  /// Parse status string to enum
  static DownloadStatus _parseStatus(String statusString) {
    return DownloadStatus.values.firstWhere(
      (status) => status.toString() == statusString,
      orElse: () => DownloadStatus.pending,
    );
  }

  /// Check if download can be retried
  bool canRetry() => retryCount < maxRetries && status == DownloadStatus.failed;

  /// Get percentage for UI display
  int getPercentage() => (progress * 100).toInt();

  /// Get formatted bytes downloaded
  String getFormattedBytes() {
    return _formatBytes(bytesDownloaded);
  }

  /// Get formatted total bytes
  String getFormattedTotalBytes() {
    // For completed downloads, use actual downloaded size
    if (status == DownloadStatus.completed) {
      return _formatBytes(bytesDownloaded);
    }
    return _formatBytes(totalBytes);
  }

  /// Format bytes to human-readable string
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
