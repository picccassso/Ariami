import 'package:ariami_core/ariami_core.dart'
    show
        ListeningAlbumRollup,
        ListeningArtistRollup,
        ListeningPeriodStats,
        ListeningSongRollup,
        StatsRange;

import '../../models/album_stats.dart';
import '../../models/artist_stats.dart';
import '../../models/song_stats.dart';

/// The range model lives in ariami_core so mobile and desktop agree on what
/// "week"/"month" mean; re-exported here for the mobile stats UI.
export 'package:ariami_core/ariami_core.dart' show StatsRange, StatsRangeKind;

typedef DayStatsFetch = Future<Map<String, dynamic>> Function(
  String date,
  int limit,
);
typedef PeriodStatsFetch = Future<Map<String, dynamic>> Function(
  String from,
  String to,
  int limit,
);
typedef ArtistsFetch = Future<Map<String, dynamic>> Function(int limit);

/// Fetches server-derived period stats and adapts them to the mobile display
/// models. All failures (offline, old server without the new endpoints,
/// malformed payloads) surface as null so the screen can degrade cleanly.
///
/// Note: unlike the all-time overlay, period views reflect server-synced
/// events only — this device's still-pending outbox events appear once they
/// upload (merging them here would need client-side credited-artist
/// splitting, which is deliberately server-only).
class PeriodStatsLoader {
  PeriodStatsLoader({
    required this.fetchDay,
    required this.fetchPeriod,
    required this.fetchArtists,
  });

  final DayStatsFetch fetchDay;
  final PeriodStatsFetch fetchPeriod;
  final ArtistsFetch fetchArtists;

  /// Loads stats for [range]; null for all-time ranges or on any failure.
  Future<ListeningPeriodStats?> load(
    StatsRange range, {
    DateTime? now,
    int limit = 50,
  }) async {
    final bounds = range.bounds(now: now);
    if (bounds == null) return null;
    try {
      final json = range.isSingleDay
          ? await fetchDay(bounds.from, limit)
          : await fetchPeriod(bounds.from, bounds.to, limit);
      return _hideUncountedRankings(ListeningPeriodStats.fromJson(json));
    } catch (_) {
      return null; // Old server / offline: the caller shows a fallback.
    }
  }

  /// Loads the all-time top credited artists; null when unavailable.
  Future<List<ListeningArtistRollup>?> loadAllTimeArtists(
      {int limit = 200}) async {
    try {
      final json = await fetchArtists(limit);
      return (json['artists'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ListeningArtistRollup.fromJson)
          .where((rollup) => rollup.artistKey.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }
}

/// Keeps partial listening in period/day totals while requiring a counted play
/// for ranked track, artist, and album entries. Older servers may already have
/// zero-play daily rollups, so filtering the response also removes those rows
/// for existing devices as soon as the mobile app is updated.
ListeningPeriodStats _hideUncountedRankings(ListeningPeriodStats stats) {
  return ListeningPeriodStats(
    fromDay: stats.fromDay,
    toDay: stats.toDay,
    totalPlays: stats.totalPlays,
    totalListenedMs: stats.totalListenedMs,
    songs: stats.songs.where((rollup) => rollup.playCount > 0).toList(),
    artists: stats.artists.where((rollup) => rollup.playCount > 0).toList(),
    albums: stats.albums.where((rollup) => rollup.playCount > 0).toList(),
    days: stats.days,
  );
}

/// Adapts server song rollups to the mobile display model.
List<SongStats> songStatsFromRollups(Iterable<ListeningSongRollup> rollups) {
  return [
    for (final rollup in rollups)
      if (rollup.playCount > 0)
        SongStats(
          songId: rollup.songId,
          playCount: rollup.playCount,
          totalTime: Duration(milliseconds: rollup.listenedMs),
          firstPlayed: rollup.firstPlayedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(rollup.firstPlayedMs!)
              : null,
          lastPlayed: rollup.lastPlayedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(rollup.lastPlayedMs!)
              : null,
          songTitle: rollup.songTitle,
          songArtist: rollup.songArtist,
          albumId: rollup.albumId,
          album: rollup.album,
          albumArtist: rollup.albumArtist,
        ),
  ];
}

/// Adapts server credited-artist rollups to the mobile display model.
///
/// The server splits combined artist strings, so a play of "Mercy" yields
/// separate rows for Kanye West, Big Sean, Pusha T and 2 Chainz. Artwork and
/// song counts aren't part of the rollup; they're recovered by matching the
/// credited name back against the songs' combined artist strings.
List<ArtistStats> artistStatsFromCredited(
  Iterable<ListeningArtistRollup> artists,
  Iterable<SongStats> songs,
) {
  final songList = songs.toList();
  final result = <ArtistStats>[];
  for (final rollup in artists) {
    if (rollup.playCount <= 0) continue;
    final display = rollup.artistDisplay ?? rollup.artistKey;
    final needle = display.toLowerCase();
    String? artworkAlbumId;
    String? artworkSongId;
    var matchedSongs = 0;
    for (final song in songList) {
      final haystack =
          '${song.songArtist ?? ''}\n${song.albumArtist ?? ''}'.toLowerCase();
      if (!haystack.contains(needle)) continue;
      matchedSongs++;
      artworkAlbumId ??= song.albumId;
      if (song.albumId == null || song.albumId!.isEmpty) {
        artworkSongId ??= song.songId;
      }
    }
    result.add(ArtistStats(
      artistName: display,
      playCount: rollup.playCount,
      totalTime: Duration(milliseconds: rollup.listenedMs),
      firstPlayed: rollup.firstPlayedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(rollup.firstPlayedMs!)
          : null,
      lastPlayed: rollup.lastPlayedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(rollup.lastPlayedMs!)
          : null,
      randomAlbumId: artworkAlbumId,
      randomSongId: artworkSongId,
      uniqueSongsCount: matchedSongs,
    ));
  }
  return result;
}

/// Adapts server album rollups to the mobile display model. Rollups keyed by
/// a normalized name (no catalog albumId) keep an empty id, which display
/// code must treat as "no artwork". Song counts aren't part of the rollup,
/// so [AlbumStats.uniqueSongsCount] is 0 and rows should show plays instead.
List<AlbumStats> albumStatsFromRollups(
    Iterable<ListeningAlbumRollup> rollups) {
  return [
    for (final rollup in rollups)
      if (rollup.playCount > 0)
        AlbumStats(
          albumId: rollup.albumId ?? '',
          albumName: rollup.album,
          albumArtist: rollup.albumArtist,
          playCount: rollup.playCount,
          totalTime: Duration(milliseconds: rollup.listenedMs),
          firstPlayed: rollup.firstPlayedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(rollup.firstPlayedMs!)
              : null,
          lastPlayed: rollup.lastPlayedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(rollup.lastPlayedMs!)
              : null,
          uniqueSongsCount: 0,
        ),
  ];
}
