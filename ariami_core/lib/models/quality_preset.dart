/// Quality presets for audio streaming and downloads.
///
/// Used to request transcoded versions of audio files at different
/// quality levels to save bandwidth on poor connections.
enum QualityPreset {
  /// Original file quality - no transcoding
  high,

  /// Medium quality - 128 kbps AAC
  medium,

  /// Low quality - 64 kbps AAC
  low;

  /// Returns the bitrate in kbps for this preset.
  /// Returns null for [high] since it uses original file.
  int? get bitrate {
    switch (this) {
      case QualityPreset.high:
        return null;
      case QualityPreset.medium:
        return 128;
      case QualityPreset.low:
        return 64;
    }
  }

  /// Returns the file extension for transcoded files.
  /// Returns null for [high] since it uses original file.
  String? get fileExtension {
    switch (this) {
      case QualityPreset.high:
        return null;
      case QualityPreset.medium:
      case QualityPreset.low:
        return 'm4a';
    }
  }

  /// Returns the MIME type for this preset.
  /// Returns null for [high] since MIME depends on original file.
  String? get mimeType {
    switch (this) {
      case QualityPreset.high:
        return null;
      case QualityPreset.medium:
      case QualityPreset.low:
        return 'audio/mp4';
    }
  }

  /// Human-readable display name
  String get displayName {
    switch (this) {
      case QualityPreset.high:
        return 'High (Original)';
      case QualityPreset.medium:
        return 'Medium (128 kbps)';
      case QualityPreset.low:
        return 'Low (64 kbps)';
    }
  }

  /// Short display name for compact UI
  String get shortName {
    switch (this) {
      case QualityPreset.high:
        return 'High';
      case QualityPreset.medium:
        return 'Medium';
      case QualityPreset.low:
        return 'Low';
    }
  }

  /// Whether this preset requires transcoding
  bool get requiresTranscoding => this != QualityPreset.high;

  /// Parse from string (e.g., from query parameter)
  /// Returns [high] if string is null, empty, or unrecognized.
  static QualityPreset fromString(String? value) {
    if (value == null || value.isEmpty) return QualityPreset.high;

    switch (value.toLowerCase()) {
      case 'high':
        return QualityPreset.high;
      case 'medium':
        return QualityPreset.medium;
      case 'low':
        return QualityPreset.low;
      default:
        return QualityPreset.high;
    }
  }

  /// Convert to string for query parameters
  String toQueryParam() => name;
}
