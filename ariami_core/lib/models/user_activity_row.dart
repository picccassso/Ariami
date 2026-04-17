/// Aggregated download/transcode activity for a single user.
class UserActivityRow {
  const UserActivityRow({
    required this.userId,
    required this.username,
    required this.isDownloading,
    required this.isTranscoding,
    required this.activeDownloads,
    required this.queuedDownloads,
    required this.inFlightDownloadTranscodes,
  });

  final String userId;
  final String username;
  final bool isDownloading;
  final bool isTranscoding;
  final int activeDownloads;
  final int queuedDownloads;
  final int inFlightDownloadTranscodes;

  factory UserActivityRow.fromJson(Map<String, dynamic> json) {
    return UserActivityRow(
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown User',
      isDownloading: json['isDownloading'] as bool? ?? false,
      isTranscoding: json['isTranscoding'] as bool? ?? false,
      activeDownloads: json['activeDownloads'] as int? ?? 0,
      queuedDownloads: json['queuedDownloads'] as int? ?? 0,
      inFlightDownloadTranscodes:
          json['inFlightDownloadTranscodes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'isDownloading': isDownloading,
      'isTranscoding': isTranscoding,
      'activeDownloads': activeDownloads,
      'queuedDownloads': queuedDownloads,
      'inFlightDownloadTranscodes': inFlightDownloadTranscodes,
    };
  }
}
