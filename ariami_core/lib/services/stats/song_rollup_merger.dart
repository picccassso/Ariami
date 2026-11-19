import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:ariami_core/utils/text_sanitizer.dart';

String _normalizeTrackTitle(String title) {
  var s = sanitizeTagText(title).toLowerCase();
  s = s.replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-');
  s = s.replaceAll(RegExp('[\u2018\u2019\u02bc]'), "'");
  s = s.replaceAll(RegExp('[\u201c\u201d]'), '"');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Canonical track identity from normalized title + order-independent credited
/// artists. Returns null if either title or artist is missing so incomplete
/// metadata never collides.
String? canonicalTrackKey(
  String? title,
  String? artist, {
  CreditedArtistSplitter? splitter,
}) {
  if (title == null || artist == null) return null;
  final normTitle = _normalizeTrackTitle(title);
  if (normTitle.isEmpty) return null;
  final credits = (splitter ?? CreditedArtistSplitter()).split(artist);
  if (credits.isEmpty) return null;
  final keys = credits.map((c) => c.key).toSet().toList()..sort();
  return '$normTitle\u0000${keys.join('\u0001')}';
}

/// Collapses song rollups that represent the same track across different file
/// paths, reordered artist credits, or separator/casing variants.
///
/// Preserves a real representative `songId` (preferring live library tracks,
/// then non-synthetic IDs, then rows with album metadata, then highest
/// listened time) so artwork and library lookups continue to work.
List<ListeningSongRollup> mergeSongRollups(
  Iterable<ListeningSongRollup> rollups, {
  CreditedArtistSplitter? splitter,
  bool Function(String songId)? isLiveSong,
}) {
  final effectiveSplitter = splitter ?? CreditedArtistSplitter();
  final groups = <String, List<ListeningSongRollup>>{};

  for (final rollup in rollups) {
    final key = canonicalTrackKey(
          rollup.songTitle,
          rollup.songArtist ?? rollup.albumArtist,
          splitter: effectiveSplitter,
        ) ??
        'id:${rollup.songId}';
    groups.putIfAbsent(key, () => <ListeningSongRollup>[]).add(rollup);
  }

  final merged = <ListeningSongRollup>[];
  for (final group in groups.values) {
    if (group.length == 1) {
      merged.add(group.single);
      continue;
    }

    int rankOf(ListeningSongRollup r) {
      final synthetic = r.songId.startsWith('spotify-uri:');
      final live = !synthetic && (isLiveSong?.call(r.songId) ?? false);
      final hasAlbum = r.albumId != null && r.albumId!.isNotEmpty;
      return (live ? 4 : 0) + (!synthetic ? 2 : 0) + (hasAlbum ? 1 : 0);
    }

    group.sort((a, b) {
      final byRank = rankOf(b).compareTo(rankOf(a));
      if (byRank != 0) return byRank;
      final byMs = b.listenedMs.compareTo(a.listenedMs);
      if (byMs != 0) return byMs;
      return b.playCount.compareTo(a.playCount);
    });

    final rep = group.first;
    var playCount = 0;
    var listenedMs = 0;
    int? firstPlayedMs;
    int? lastPlayedMs;
    String? songTitle;
    String? songArtist;
    String? albumId;
    String? album;
    String? albumArtist;

    for (final r in group) {
      playCount += r.playCount;
      listenedMs += r.listenedMs;
      if (r.firstPlayedMs != null &&
          (firstPlayedMs == null || r.firstPlayedMs! < firstPlayedMs)) {
        firstPlayedMs = r.firstPlayedMs;
      }
      if (r.lastPlayedMs != null &&
          (lastPlayedMs == null || r.lastPlayedMs! > lastPlayedMs)) {
        lastPlayedMs = r.lastPlayedMs;
      }
      songTitle ??= _nonEmpty(r.songTitle);
      songArtist ??= _nonEmpty(r.songArtist);
      albumId ??= _nonEmpty(r.albumId);
      album ??= _nonEmpty(r.album);
      albumArtist ??= _nonEmpty(r.albumArtist);
    }

    merged.add(ListeningSongRollup(
      songId: rep.songId,
      playCount: playCount,
      listenedMs: listenedMs,
      firstPlayedMs: firstPlayedMs,
      lastPlayedMs: lastPlayedMs,
      songTitle: songTitle,
      songArtist: songArtist,
      albumId: albumId,
      album: album,
      albumArtist: albumArtist,
    ));
  }

  return merged;
}

String? _nonEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : value;
}
