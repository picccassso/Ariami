import 'package:ariami_core/services/stats/credited_artist_splitter.dart';

/// `yyyy-mm-dd` in the listener's local timezone at the event time.
String statsLocalDay(int occurredAtMs, int tzOffsetMinutes) {
  final local = DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true)
      .add(Duration(minutes: tzOffsetMinutes));
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Grouping key for album rollups: catalog id when present, otherwise a
/// normalized-name key so untagged libraries still group.
String? statsAlbumKey(String? albumId, String? album) {
  if (albumId != null && albumId.isNotEmpty) return albumId;
  if (album != null) {
    final key = normalizeArtistKey(album);
    if (key.isNotEmpty) return 'name:$key';
  }
  return null;
}
