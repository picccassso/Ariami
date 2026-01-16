/// Audio quality preset for streaming/downloads
enum StreamingQuality {
  /// Original file quality (no transcoding)
  high,

  /// 128 kbps AAC
  medium,

  /// 64 kbps AAC
  low;

  /// Convert to server API parameter value
  String toApiParam() => name;

  /// Parse from stored string value
  static StreamingQuality fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'low':
        return StreamingQuality.low;
      case 'medium':
        return StreamingQuality.medium;
      case 'high':
      default:
        return StreamingQuality.high;
    }
  }

  /// Human-readable display name
  String get displayName {
    switch (this) {
      case StreamingQuality.high:
        return 'High (Original)';
      case StreamingQuality.medium:
        return 'Medium (128 kbps)';
      case StreamingQuality.low:
        return 'Low (64 kbps)';
    }
  }

  /// Description for UI
  String get description {
    switch (this) {
      case StreamingQuality.high:
        return 'Best quality, uses more data';
      case StreamingQuality.medium:
        return 'Balanced quality and data usage';
      case StreamingQuality.low:
        return 'Saves data, lower quality';
    }
  }

  /// Approximate bitrate for display
  String get bitrateLabel {
    switch (this) {
      case StreamingQuality.high:
        return 'Original';
      case StreamingQuality.medium:
        return '128 kbps';
      case StreamingQuality.low:
        return '64 kbps';
    }
  }
}

/// User's quality preferences for different network conditions
class QualitySettings {
  /// Quality to use when on WiFi
  final StreamingQuality wifiQuality;

  /// Quality to use when on mobile data
  final StreamingQuality mobileDataQuality;

  /// Quality for downloads (always uses this regardless of network)
  final StreamingQuality downloadQuality;

  const QualitySettings({
    this.wifiQuality = StreamingQuality.high,
    this.mobileDataQuality = StreamingQuality.medium,
    this.downloadQuality = StreamingQuality.high,
  });

  /// Create from JSON (for persistence)
  factory QualitySettings.fromJson(Map<String, dynamic> json) {
    return QualitySettings(
      wifiQuality: StreamingQuality.fromString(json['wifiQuality'] as String?),
      mobileDataQuality:
          StreamingQuality.fromString(json['mobileDataQuality'] as String?),
      downloadQuality:
          StreamingQuality.fromString(json['downloadQuality'] as String?),
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'wifiQuality': wifiQuality.name,
      'mobileDataQuality': mobileDataQuality.name,
      'downloadQuality': downloadQuality.name,
    };
  }

  /// Create a copy with updated fields
  QualitySettings copyWith({
    StreamingQuality? wifiQuality,
    StreamingQuality? mobileDataQuality,
    StreamingQuality? downloadQuality,
  }) {
    return QualitySettings(
      wifiQuality: wifiQuality ?? this.wifiQuality,
      mobileDataQuality: mobileDataQuality ?? this.mobileDataQuality,
      downloadQuality: downloadQuality ?? this.downloadQuality,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QualitySettings &&
          runtimeType == other.runtimeType &&
          wifiQuality == other.wifiQuality &&
          mobileDataQuality == other.mobileDataQuality &&
          downloadQuality == other.downloadQuality;

  @override
  int get hashCode =>
      wifiQuality.hashCode ^
      mobileDataQuality.hashCode ^
      downloadQuality.hashCode;

  @override
  String toString() =>
      'QualitySettings(wifi: $wifiQuality, mobile: $mobileDataQuality, download: $downloadQuality)';
}
