import '../../../models/api_models.dart';
import '../../../models/song.dart';

/// Helper to convert SongModel to Song with album info lookup
/// Uses album info map to populate album name and artist
Song songModelToSong(
    SongModel s, Map<String, ({String name, String artist})> albumInfoMap) {
  String? albumName;
  String? albumArtist;

  // Lookup album info if song has albumId
  if (s.albumId != null && albumInfoMap.containsKey(s.albumId)) {
    final albumInfo = albumInfoMap[s.albumId]!;
    albumName = albumInfo.name;
    albumArtist = albumInfo.artist;
  }

  return Song(
    id: s.id,
    title: s.title,
    artist: s.artist,
    album: albumName,
    albumId: s.albumId,
    albumArtist: albumArtist,
    duration: Duration(seconds: s.duration),
    trackNumber: s.trackNumber,
    filePath: s.id, // Use song ID as placeholder
    fileSize: 0,
    modifiedTime: DateTime.now(),
  );
}

/// Format duration in seconds to MM:SS format
String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

/// Format playlist total duration in a human-readable form.
///
/// Examples:
/// - 540s  -> 9 min
/// - 5520s -> 1 hour 32 mins
String formatPlaylistTotalDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;

  if (hours == 0) {
    return '$minutes min';
  }

  final hourLabel = hours == 1 ? 'hour' : 'hours';
  if (minutes == 0) {
    return '$hours $hourLabel';
  }

  return '$hours $hourLabel $minutes mins';
}
