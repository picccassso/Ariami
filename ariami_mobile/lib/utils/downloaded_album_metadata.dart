import '../models/download_task.dart';

String resolveDownloadedAlbumArtist(Iterable<DownloadTask> tasks) {
  final albumTasks = tasks.toList();
  if (albumTasks.isEmpty) return 'Unknown Artist';

  final albumArtists = _distinctArtists(
    albumTasks.map((task) => _resolvedAlbumArtist(task)),
  );
  final specificAlbumArtists =
      albumArtists.where((artist) => !_isGenericArtist(artist)).toList();
  if (specificAlbumArtists.isNotEmpty) return specificAlbumArtists.first;

  final songArtists = _distinctArtists(
    albumTasks.map((task) => task.artist),
  );
  if (songArtists.length == 1) return songArtists.single;

  if (albumArtists.isNotEmpty) return albumArtists.first;
  return songArtists.isNotEmpty ? songArtists.first : 'Unknown Artist';
}

String? _resolvedAlbumArtist(DownloadTask task) {
  final albumArtist = task.albumArtist?.trim();
  if (albumArtist == null || albumArtist.isEmpty) {
    return task.artist;
  }

  final trackArtist = _primaryTrackArtist(task.artist);
  final cleanedChannelArtist =
      _cleanYouTubeChannelArtist(albumArtist, trackArtist);
  if (cleanedChannelArtist != null) {
    return cleanedChannelArtist;
  }

  return albumArtist;
}

List<String> _distinctArtists(Iterable<String?> artists) {
  final artistsByNormalizedName = <String, String>{};
  for (final artist in artists) {
    final trimmed = artist?.trim();
    if (trimmed == null || trimmed.isEmpty) continue;
    artistsByNormalizedName.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
  }
  return artistsByNormalizedName.values.toList();
}

bool _isGenericArtist(String artist) =>
    artist.trim().toLowerCase() == 'various artists';

String? _primaryTrackArtist(String? artist) {
  var value = artist?.trim();
  if (value == null || value.isEmpty) return null;

  value = value
      .replaceAll(
        RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+.+$', caseSensitive: false),
        '',
      )
      .trim();

  final comma = value.indexOf(',');
  if (comma >= 0) {
    value = value.substring(0, comma).trim();
  }

  return value.isEmpty ? null : value;
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
