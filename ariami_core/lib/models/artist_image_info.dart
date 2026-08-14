import 'dart:typed_data';

/// Metadata for a stored artist image, without the raw image bytes.
class ArtistImageInfo {
  const ArtistImageInfo({
    required this.artistKey,
    required this.artistName,
    required this.contentType,
    required this.updatedAt,
  });

  /// Normalized grouping key for the artist (e.g. lowercase, trimmed).
  final String artistKey;

  /// Display name of the artist.
  final String artistName;

  /// MIME type of the image (`image/jpeg`, `image/png`, `image/webp`).
  final String contentType;

  /// Milliseconds since epoch (UTC). Strictly increases per artist so
  /// clients can use it as a cache-busting version.
  final int updatedAt;

  factory ArtistImageInfo.fromJson(Map<String, dynamic> json) =>
      ArtistImageInfo(
        artistKey: json['artistKey'] as String? ?? '',
        artistName: json['artistName'] as String? ?? '',
        contentType: json['contentType'] as String? ?? 'image/jpeg',
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'artistKey': artistKey,
        'artistName': artistName,
        'contentType': contentType,
        'updatedAt': updatedAt,
      };
}

/// A stored artist image, including its raw bytes.
class ArtistImageRecord extends ArtistImageInfo {
  const ArtistImageRecord({
    required super.artistKey,
    required super.artistName,
    required super.contentType,
    required super.updatedAt,
    required this.bytes,
  });

  final Uint8List bytes;
}
