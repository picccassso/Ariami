import 'package:ariami_core/models/song_metadata.dart';

/// Shared album grouping logic for [AlbumBuilder] and [ChangeProcessor].
///
/// Rules:
/// 1. Non-empty **album artist** (TPE2) wins — use it as-is (trimmed),
///    unless it looks like a YouTube channel name derived from the track artist
///    such as "EminemMusic" or "NFrealmusic".
/// 2. Otherwise normalize **track artist** (TPE1): strip trailing
///    `feat.` / `ft.` / `featuring …`, then take the first comma-separated
///    segment. This merges "Eminem" with "Eminem, Jessie Reyez" when tags
///    omit album artist.

final RegExp _trailingFeatPattern = RegExp(
  r'\s+(?:feat\.?|ft\.?|featuring)\s+.+$',
  caseSensitive: false,
);

final RegExp _albumPrefixPattern =
    RegExp(r'^album\s*[-:–—]\s*', caseSensitive: false);

const List<String> _youtubeChannelArtistSuffixes = [
  'officialmusic',
  'realmusic',
  'official',
  'youtube',
  'vevo',
  'topic',
  'music',
  'yt',
];

/// Artist string used for album grouping and album-level display.
String? albumGroupingArtist(SongMetadata song) {
  final albumArtist = song.albumArtist?.trim();
  final trackArtist = _primaryArtistForGrouping(song.artist);
  if (albumArtist != null && albumArtist.isNotEmpty) {
    final cleanedChannelArtist =
        _cleanYouTubeChannelArtist(albumArtist, trackArtist);
    if (cleanedChannelArtist != null) {
      return cleanedChannelArtist;
    }
    return albumArtist;
  }
  return trackArtist;
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

String? _cleanYouTubeChannelArtist(String albumArtist, String? trackArtist) {
  final normalizedAlbumArtist = _normalizeArtistChannelName(albumArtist);
  final normalizedTrackArtist =
      trackArtist == null ? null : _normalizeArtistChannelName(trackArtist);
  if (normalizedTrackArtist != null &&
      normalizedTrackArtist.isNotEmpty &&
      normalizedAlbumArtist != normalizedTrackArtist &&
      normalizedAlbumArtist.startsWith(normalizedTrackArtist)) {
    final suffix =
        normalizedAlbumArtist.substring(normalizedTrackArtist.length);
    if (_youtubeChannelArtistSuffixes.contains(suffix)) {
      return trackArtist;
    }
  }

  final suffix = _directlyAppendedChannelSuffix(albumArtist);
  if (suffix == null) return null;

  final stripped = albumArtist.substring(0, albumArtist.length - suffix.length);
  return stripped.trim().isEmpty ? null : stripped.trim();
}

String? _directlyAppendedChannelSuffix(String value) {
  for (final suffix in _youtubeChannelArtistSuffixes) {
    if (!value.toLowerCase().endsWith(suffix)) continue;

    final prefixLength = value.length - suffix.length;
    if (prefixLength <= 0) continue;

    final charBeforeSuffix = value[prefixLength - 1];
    if (RegExp(r'[A-Za-z0-9]').hasMatch(charBeforeSuffix)) {
      return value.substring(prefixLength);
    }
  }

  return null;
}

String _normalizeArtistChannelName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();
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
