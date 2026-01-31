/// Size presets for album artwork.
///
/// Used to request different sizes of artwork from the server.
/// Thumbnails are smaller and faster to load, suitable for list views.
/// Full size is the original artwork, suitable for detail views.
enum ArtworkSize {
  /// Thumbnail for list views (200x200 max)
  thumbnail,

  /// Full quality for detail views (original size)
  full;

  /// Returns the max dimension for this size (null = original).
  int? get maxDimension {
    switch (this) {
      case ArtworkSize.thumbnail:
        return 200;
      case ArtworkSize.full:
        return null;
    }
  }

  /// Whether this size requires processing (resizing).
  bool get requiresProcessing => this == ArtworkSize.thumbnail;

  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case ArtworkSize.thumbnail:
        return 'Thumbnail';
      case ArtworkSize.full:
        return 'Full';
    }
  }

  /// Parse from string (e.g., query parameter).
  ///
  /// Returns [ArtworkSize.full] for null, empty, or unrecognized values
  /// to maintain backward compatibility.
  static ArtworkSize fromString(String? value) {
    if (value == null || value.isEmpty) return ArtworkSize.full;
    switch (value.toLowerCase()) {
      case 'thumbnail':
      case 'thumb':
        return ArtworkSize.thumbnail;
      case 'full':
      case 'original':
      default:
        return ArtworkSize.full;
    }
  }

  /// Convert to query parameter string.
  String toQueryParam() => name;
}
