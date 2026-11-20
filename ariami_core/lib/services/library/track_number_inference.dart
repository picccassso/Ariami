import 'package:path/path.dart' as path;

import 'package:ariami_core/models/song_metadata.dart';

/// Attempts to infer track number from filename prefixes like:
/// "01 - Title", "1. Title", "07_Title", "12 Title".
int? inferTrackNumberFromFilename(String filePath) {
  final fileName = path.basenameWithoutExtension(filePath).trim();
  final match = RegExp(r'^(\d{1,3})(?:\s*[-._)]\s*|\s+)').firstMatch(fileName);
  if (match == null) return null;

  final parsed = int.tryParse(match.group(1)!);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

/// Some taggers write the same track number on every file of an album. When
/// two different songs from one album in one folder share a number, the tags
/// can't be trusted, so those songs take their filename's leading number.
List<SongMetadata> repairCollidingTrackNumbers(List<SongMetadata> songs) {
  final groups = <String, List<int>>{};
  for (var i = 0; i < songs.length; i++) {
    final song = songs[i];
    if (song.trackNumber == null) continue;
    final key = '${path.dirname(song.filePath)}|${song.album}|'
        '${song.discNumber ?? 1}|${song.trackNumber}';
    groups.putIfAbsent(key, () => <int>[]).add(i);
  }
  final repaired = List<SongMetadata>.of(songs);
  for (final indices in groups.values) {
    if (indices.map((i) => songs[i].title).toSet().length < 2) continue;
    for (final i in indices) {
      final inferred = inferTrackNumberFromFilename(songs[i].filePath);
      if (inferred != null) {
        repaired[i] = songs[i].copyWith(trackNumber: inferred);
      }
    }
  }
  return repaired;
}
