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
typedef PeriodStatsCacheRead = Future<Map<String, dynamic>?> Function(
  String from,
  String to,
);
typedef PeriodStatsCacheWrite = Future<void> Function(
  String from,
  String to,
  Map<String, dynamic> stats,
);

/// Fetches server-derived period stats and adapts them to the mobile display
/// models. Successful responses can be persisted through [writeCached]; on a
/// fetch failure (offline or an old server), the exact cached range is reused
/// through [readCached]. Null means neither source had a usable snapshot.
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
    this.readCached,
    this.writeCached,
  });

  final DayStatsFetch fetchDay;
  final PeriodStatsFetch fetchPeriod;
  final ArtistsFetch fetchArtists;
  final PeriodStatsCacheRead? readCached;
  final PeriodStatsCacheWrite? writeCached;

  /// Loads stats for [range]; null for all-time ranges or on any failure.
  /// The default limit 0 asks for every ranked entry; servers that predate
  /// that special value get one retry at their old default cap.
  Future<ListeningPeriodStats?> load(
    StatsRange range, {
    DateTime? now,
    int limit = 0,
  }) async {
    final bounds = range.bounds(now: now);
    if (bounds == null) return null;
    Future<Map<String, dynamic>> fetch(int limit) => range.isSingleDay
        ? fetchDay(bounds.from, limit)
        : fetchPeriod(bounds.from, bounds.to, limit);
    try {
      Map<String, dynamic> json;
      try {
        json = await fetch(limit);
      } catch (_) {
        if (limit != 0) rethrow;
        json = await fetch(50);
      }
      final stats = _parse(json);
      try {
        await writeCached?.call(bounds.from, bounds.to, stats.toJson());
      } catch (_) {
        // The network result remains usable when best-effort caching fails.
      }
      return stats;
    } catch (_) {
      try {
        final json = await readCached?.call(bounds.from, bounds.to);
        return json == null ? null : _parse(json);
      } catch (_) {
        return null; // No valid cached snapshot: show the offline fallback.
      }
    }
  }

  /// Reads the cached snapshot for [range] without touching the network, so
  /// the screen can show a previously viewed range instantly while the fresh
  /// fetch replaces it (stale-while-revalidate). Null with no valid cache.
  Future<ListeningPeriodStats?> loadCached(
    StatsRange range, {
    DateTime? now,
  }) async {
    final bounds = range.bounds(now: now);
    if (bounds == null) return null;
    try {
      final json = await readCached?.call(bounds.from, bounds.to);
      return json == null ? null : _parse(json);
    } catch (_) {
      return null;
    }
  }

  /// Loads the all-time top credited artists; null when unavailable. The
  /// default limit 0 asks for every artist, retrying once at the old capped
  /// maximum for servers that reject the special value.
  Future<List<ListeningArtistRollup>?> loadAllTimeArtists(
      {int limit = 0}) async {
    try {
      Map<String, dynamic> json;
      try {
        json = await fetchArtists(limit);
      } catch (_) {
        if (limit != 0) rethrow;
        json = await fetchArtists(200);
      }
      return (json['artists'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ListeningArtistRollup.fromJson)
          .where((rollup) => rollup.artistKey.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  ListeningPeriodStats _parse(Map<String, dynamic> json) =>
      _hideUncountedRankings(ListeningPeriodStats.fromJson(json));
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
  // The scan is O(artists × songs); lower each song's combined artist string
  // once here rather than once per artist, which dominated the cost on large
  // uncapped lists.
  final haystacks = List<String>.generate(
    songList.length,
    (i) =>
        '${songList[i].songArtist ?? ''}\n${songList[i].albumArtist ?? ''}'
            .toLowerCase(),
    growable: false,
  );
  final result = <ArtistStats>[];
  for (final rollup in artists) {
    if (rollup.playCount <= 0) continue;
    final display = rollup.artistDisplay ?? rollup.artistKey;
    final needle = display.toLowerCase();
    String? artworkAlbumId;
    String? artworkSongId;
    var matchedSongs = 0;
    for (var i = 0; i < songList.length; i++) {
      if (!haystacks[i].contains(needle)) continue;
      final song = songList[i];
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
