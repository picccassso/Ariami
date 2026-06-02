import '../models/download_task.dart';

String resolveDownloadedAlbumArtist(Iterable<DownloadTask> tasks) {
  final albumTasks = tasks.toList();
  if (albumTasks.isEmpty) return 'Unknown Artist';

  final albumArtists = _distinctArtists(
    albumTasks.map((task) => task.albumArtist),
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
