enum StreamingQuality {
  /// Original file quality (no transcoding)
  high,

  /// 128 kbps AAC
  medium,

  /// 64 kbps AAC
  low;

  String toApiParam() => name;

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
}

/// Quality preset for offline downloads.
///
/// [original] downloads the untouched source file from the server.
/// [high], [medium], and [low] request transcoding on the server via Sonic.
enum DownloadQuality {
  original,
  high,
  medium,
  low;

  String get displayName {
    switch (this) {
      case DownloadQuality.original:
        return 'Original';
      case DownloadQuality.high:
        return 'High (192 kbps)';
      case DownloadQuality.medium:
        return 'Medium (128 kbps)';
      case DownloadQuality.low:
        return 'Low (64 kbps)';
    }
  }

  String get description {
    switch (this) {
      case DownloadQuality.original:
        return 'Original source file';
      case DownloadQuality.high:
        return 'Best compressed quality';
      case DownloadQuality.medium:
        return 'Balanced quality and storage';
      case DownloadQuality.low:
        return 'Smallest downloads';
    }
  }

  /// Maps to the underlying [StreamingQuality] preset used by the API ticket
  StreamingQuality get streamingQuality => switch (this) {
        DownloadQuality.original || DownloadQuality.high => StreamingQuality.high,
        DownloadQuality.medium => StreamingQuality.medium,
        DownloadQuality.low => StreamingQuality.low,
      };

  bool get isOriginal => this == DownloadQuality.original;

  static DownloadQuality fromSettings({
    required StreamingQuality quality,
    required bool isOriginal,
  }) {
    if (isOriginal) return DownloadQuality.original;
    return switch (quality) {
      StreamingQuality.high => DownloadQuality.high,
      StreamingQuality.medium => DownloadQuality.medium,
      StreamingQuality.low => DownloadQuality.low,
    };
  }

  static DownloadQuality fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'original':
        return DownloadQuality.original;
      case 'high':
        return DownloadQuality.high;
      case 'medium':
        return DownloadQuality.medium;
      case 'low':
        return DownloadQuality.low;
      default:
        return DownloadQuality.original;
    }
  }
}

class QualitySettings {
  final StreamingQuality wifiQuality;

  final StreamingQuality mobileDataQuality;

  /// Quality for downloads (always uses this regardless of network)
  final StreamingQuality downloadQuality;

  /// Prefer downloaded/cached files when online (instead of streaming)
  final bool preferLocalWhenOnline;

  /// Whether downloads should use the original file (skip transcoding)
  final bool downloadOriginal;

  /// Effective download quality encompassing original vs transcoded high/medium/low
  DownloadQuality get effectiveDownloadQuality =>
      DownloadQuality.fromSettings(
        quality: downloadQuality,
        isOriginal: downloadOriginal,
      );

  const QualitySettings({
    this.wifiQuality = StreamingQuality.high,
    this.mobileDataQuality = StreamingQuality.medium,
    this.downloadQuality = StreamingQuality.high,
    this.preferLocalWhenOnline = false,
    this.downloadOriginal = false,
  });

  factory QualitySettings.fromJson(Map<String, dynamic> json) {
    final rawDownloadQuality = json['downloadQuality'] as String?;
    final rawEffectiveQuality = json['effectiveDownloadQuality'] as String?;
    final isOriginalQuality = rawDownloadQuality?.toLowerCase() == 'original' ||
        rawEffectiveQuality?.toLowerCase() == 'original';
    final downloadOriginal =
        (json['downloadOriginal'] as bool? ?? false) || isOriginalQuality;
    final downloadQuality = isOriginalQuality
        ? StreamingQuality.high
        : (rawEffectiveQuality != null
            ? DownloadQuality.fromString(rawEffectiveQuality).streamingQuality
            : StreamingQuality.fromString(rawDownloadQuality));

    return QualitySettings(
      wifiQuality: StreamingQuality.fromString(json['wifiQuality'] as String?),
      mobileDataQuality:
          StreamingQuality.fromString(json['mobileDataQuality'] as String?),
      downloadQuality: downloadQuality,
      preferLocalWhenOnline: json['preferLocalWhenOnline'] as bool? ?? false,
      downloadOriginal: downloadOriginal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wifiQuality': wifiQuality.name,
      'mobileDataQuality': mobileDataQuality.name,
      'downloadQuality': downloadQuality.name,
      'preferLocalWhenOnline': preferLocalWhenOnline,
      'downloadOriginal': downloadOriginal,
      'effectiveDownloadQuality': effectiveDownloadQuality.name,
    };
  }

  QualitySettings copyWith({
    StreamingQuality? wifiQuality,
    StreamingQuality? mobileDataQuality,
    StreamingQuality? downloadQuality,
    bool? preferLocalWhenOnline,
    bool? downloadOriginal,
    DownloadQuality? effectiveDownloadQuality,
  }) {
    final resolvedQuality = effectiveDownloadQuality != null
        ? effectiveDownloadQuality.streamingQuality
        : (downloadQuality ?? this.downloadQuality);
    final resolvedOriginal = effectiveDownloadQuality != null
        ? effectiveDownloadQuality.isOriginal
        : (downloadOriginal ?? this.downloadOriginal);

    return QualitySettings(
      wifiQuality: wifiQuality ?? this.wifiQuality,
      mobileDataQuality: mobileDataQuality ?? this.mobileDataQuality,
      downloadQuality: resolvedQuality,
      preferLocalWhenOnline:
          preferLocalWhenOnline ?? this.preferLocalWhenOnline,
      downloadOriginal: resolvedOriginal,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QualitySettings &&
          runtimeType == other.runtimeType &&
          wifiQuality == other.wifiQuality &&
          mobileDataQuality == other.mobileDataQuality &&
          downloadQuality == other.downloadQuality &&
          preferLocalWhenOnline == other.preferLocalWhenOnline &&
          downloadOriginal == other.downloadOriginal;

  @override
  int get hashCode =>
      wifiQuality.hashCode ^
      mobileDataQuality.hashCode ^
      downloadQuality.hashCode ^
      preferLocalWhenOnline.hashCode ^
      downloadOriginal.hashCode;

  @override
  String toString() =>
      'QualitySettings(wifi: $wifiQuality, mobile: $mobileDataQuality, '
      'download: $downloadQuality, preferLocalWhenOnline: $preferLocalWhenOnline, '
      'downloadOriginal: $downloadOriginal)';
}
