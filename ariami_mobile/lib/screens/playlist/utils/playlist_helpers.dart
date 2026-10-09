import '../../../models/api_models.dart';
import '../../../models/song.dart';
import '../../../utils/song_from_model.dart';

Song songModelToSong(
    SongModel s, Map<String, ({String name, String artist})> albumInfoMap) {
  String? albumName;
  String? albumArtist;

  if (s.albumId != null && albumInfoMap.containsKey(s.albumId)) {
    final albumInfo = albumInfoMap[s.albumId]!;
    albumName = albumInfo.name;
    albumArtist = albumInfo.artist;
  }

  return songFromModel(s, album: albumName, albumArtist: albumArtist);
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
