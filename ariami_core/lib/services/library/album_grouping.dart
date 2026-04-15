import 'package:ariami_core/models/song_metadata.dart';

/// Shared album grouping logic for [AlbumBuilder] and [ChangeProcessor].
///
/// Rules:
/// 1. Non-empty **album artist** (TPE2) wins — use it as-is (trimmed).
/// 2. Otherwise normalize **track artist** (TPE1): strip trailing
///    `feat.` / `ft.` / `featuring …`, then take the first comma-separated
///    segment. This merges "Eminem" with "Eminem, Jessie Reyez" when tags
///    omit album artist.

final RegExp _trailingFeatPattern = RegExp(
  r'\s+(?:feat\.?|ft\.?|featuring)\s+.+$',
  caseSensitive: false,
);

final RegExp _albumPrefixPattern = RegExp(r'^album\s*[-:–—]\s*', caseSensitive: false);

/// Artist string used only for grouping (not for display).
String? albumGroupingArtist(SongMetadata song) {
  final albumArtist = song.albumArtist?.trim();
  if (albumArtist != null && albumArtist.isNotEmpty) {
    return albumArtist;
  }
  return _primaryArtistForGrouping(song.artist);
}

/// Normalizes TPE1-style strings so featured / multi-artist credits map to one bucket.
String? _primaryArtistForGrouping(String? artist) {
  if (artist == null) return null;
  var s = artist.trim();
  if (s.isEmpty) return null;

  s = s.replaceAll(_trailingFeatPattern, '').trim();

  final comma = s.indexOf(',');
  if (comma >= 0) {
    s = s.substring(0, comma).trim();
  }

  if (s.isEmpty) return null;
  return s;
}

/// Composite key `album|||artist` for grouping, or null if not album-groupable.
String? albumGroupingKey(SongMetadata song) {
  final album = normalizeAlbumTitle(song.album);
  if (album == null || album.isEmpty) {
    return null;
  }

  final artist = albumGroupingArtist(song);
  if (artist == null || artist.isEmpty) {
    return null;
  }

  return '${album.toLowerCase()}|||${artist.toLowerCase()}';
}

/// Normalizes album titles for grouping/display stability.
///
/// - Trims whitespace
/// - Removes noisy leading prefixes like "Album - "
/// - Collapses repeated spaces
String? normalizeAlbumTitle(String? album) {
  if (album == null) return null;

  var normalized = album.trim();
  if (normalized.isEmpty) return null;

  normalized = normalized.replaceFirst(_albumPrefixPattern, '').trim();
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (normalized.isEmpty) return null;
  return normalized;
}

