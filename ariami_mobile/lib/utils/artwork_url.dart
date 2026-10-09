import '../services/api/connection_service.dart';

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

/// Cache key and server URL for a song's artwork: the album's artwork when
/// [albumId] is set, otherwise the song's own artwork. The URL is null while
/// no server connection exists.
({String cacheId, String? url}) resolveSongArtwork({
  required String songId,
  String? albumId,
}) {
  final baseUrl = ConnectionService().apiClient?.baseUrl;
  if (albumId != null) {
    return (
      cacheId: albumId,
      url: baseUrl != null ? '$baseUrl/artwork/$albumId' : null,
    );
  }
  return (
    cacheId: 'song_$songId',
    url: baseUrl != null ? '$baseUrl/song-artwork/$songId' : null,
  );
}
