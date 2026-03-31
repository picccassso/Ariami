/// Returns the best artwork URL for an album.
///
/// Prefers the explicit [coverArt] value from API data. When that is missing,
/// falls back to the deterministic server endpoint derived from [albumId].
String? resolveAlbumArtworkUrl({
  required String albumId,
  String? coverArt,
}) {
  if (coverArt != null && coverArt.isNotEmpty) {
    return coverArt;
  }

  final normalizedAlbumId = albumId.trim();
  if (normalizedAlbumId.isEmpty) {
    return null;
  }

  return '/api/artwork/${Uri.encodeComponent(normalizedAlbumId)}';
}
