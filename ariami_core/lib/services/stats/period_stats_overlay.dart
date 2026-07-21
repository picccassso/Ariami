import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:ariami_core/services/stats/stats_local_day.dart';

/// Display-only merge of [base] period stats with still-pending outbox events.
///
/// Does not mutate [base]. Server upload/sync paths are untouched — this is
/// purely for offline UI so period views don't freeze on the last server
/// snapshot while events sit in the outbox.
ListeningPeriodStats overlayPeriodStatsWithPending({
  ListeningPeriodStats? base,
  required List<ListeningEvent> pending,
  required String fromDay,
  required String toDay,
  Set<String> excludeEventIds = const {},
}) {
  var totalPlays = base?.totalPlays ?? 0;
  var totalListenedMs = base?.totalListenedMs ?? 0;

  final songs = <String, _MutableSong>{};
  for (final song in base?.songs ?? const <ListeningSongRollup>[]) {
    songs[song.songId] = _MutableSong.from(song);
  }

  final albums = <String, _MutableAlbum>{};
  for (final album in base?.albums ?? const <ListeningAlbumRollup>[]) {
    albums[album.albumKey] = _MutableAlbum.from(album);
  }

  final artists = <String, _MutableArtist>{};
  for (final artist in base?.artists ?? const <ListeningArtistRollup>[]) {
    artists[artist.artistKey] = _MutableArtist.from(artist);
  }

  final days = <String, _MutableDay>{};
  for (final entry in (base?.days ?? const <String, ListeningDailyTotal>{})
      .entries) {
    days[entry.key] = _MutableDay(
      playCount: entry.value.playCount,
      listenedMs: entry.value.listenedMs,
    );
  }

  final seenEventIds = <String>{...excludeEventIds};

  for (final event in pending) {
    if (event.eventId.startsWith('baseline:')) continue;
    if (!seenEventIds.add(event.eventId)) continue;

    final localDay =
        statsLocalDay(event.occurredAtMs, event.tzOffsetMinutes);
    if (localDay.compareTo(fromDay) < 0 || localDay.compareTo(toDay) > 0) {
      continue;
    }

    totalPlays += event.plays;
    totalListenedMs += event.listenedMs;

    final day = days.putIfAbsent(localDay, _MutableDay.new);
    day.playCount += event.plays;
    day.listenedMs += event.listenedMs;

    // Accumulate entity rows for every event; ranked lists drop playCount==0
    // afterward so pure time-only segments never invent a ranking entry.
    final song = songs.putIfAbsent(
      event.songId,
      () => _MutableSong(songId: event.songId),
    );
    song.playCount += event.plays;
    song.listenedMs += event.listenedMs;
    song.touch(event.occurredAtMs);
    song.songTitle ??= event.songTitle;
    song.songArtist ??= event.songArtist;
    song.albumId ??= event.albumId;
    song.album ??= event.album;
    song.albumArtist ??= event.albumArtist;

    final albumKey = statsAlbumKey(event.albumId, event.album);
    if (albumKey != null) {
      final album = albums.putIfAbsent(
        albumKey,
        () => _MutableAlbum(albumKey: albumKey),
      );
      album.playCount += event.plays;
      album.listenedMs += event.listenedMs;
      album.touch(event.occurredAtMs);
      album.albumId ??= event.albumId;
      album.album ??= event.album;
      album.albumArtist ??= event.albumArtist;
    }

    // Offline fallback: one combined-string artist row (not split credits).
    final rawArtist = event.songArtist ?? event.albumArtist;
    if (rawArtist != null && rawArtist.isNotEmpty) {
      final artistKey = normalizeArtistKey(rawArtist);
      if (artistKey.isNotEmpty) {
        final artist = artists.putIfAbsent(
          artistKey,
          () => _MutableArtist(artistKey: artistKey),
        );
        artist.playCount += event.plays;
        artist.listenedMs += event.listenedMs;
        artist.touch(event.occurredAtMs);
        artist.artistDisplay ??= rawArtist;
      }
    }
  }

  int byPlaysThenMs(int playA, int msA, int playB, int msB) {
    final byPlays = playB.compareTo(playA);
    return byPlays != 0 ? byPlays : msB.compareTo(msA);
  }

  final rankedSongs = songs.values
      .where((s) => s.playCount > 0)
      .map((s) => s.toRollup())
      .toList()
    ..sort((a, b) =>
        byPlaysThenMs(a.playCount, a.listenedMs, b.playCount, b.listenedMs));

  final rankedArtists = artists.values
      .where((a) => a.playCount > 0)
      .map((a) => a.toRollup())
      .toList()
    ..sort((a, b) =>
        byPlaysThenMs(a.playCount, a.listenedMs, b.playCount, b.listenedMs));

  final rankedAlbums = albums.values
      .where((a) => a.playCount > 0)
      .map((a) => a.toRollup())
      .toList()
    ..sort((a, b) =>
        byPlaysThenMs(a.playCount, a.listenedMs, b.playCount, b.listenedMs));

  final dayTotals = <String, ListeningDailyTotal>{
    for (final entry in days.entries)
      entry.key: ListeningDailyTotal(
        playCount: entry.value.playCount,
        listenedMs: entry.value.listenedMs,
      ),
  };

  return ListeningPeriodStats(
    fromDay: fromDay,
    toDay: toDay,
    totalPlays: totalPlays,
    totalListenedMs: totalListenedMs,
    songs: rankedSongs,
    artists: rankedArtists,
    albums: rankedAlbums,
    days: dayTotals,
  );
}

class _MutableDay {
  int playCount;
  int listenedMs;

  _MutableDay({this.playCount = 0, this.listenedMs = 0});
}

class _MutableSong {
  final String songId;
  int playCount;
  int listenedMs;
  int? firstPlayedMs;
  int? lastPlayedMs;
  String? songTitle;
  String? songArtist;
  String? albumId;
  String? album;
  String? albumArtist;

  _MutableSong({
    required this.songId,
    this.playCount = 0,
    this.listenedMs = 0,
    this.firstPlayedMs,
    this.lastPlayedMs,
    this.songTitle,
    this.songArtist,
    this.albumId,
    this.album,
    this.albumArtist,
  });

  factory _MutableSong.from(ListeningSongRollup s) => _MutableSong(
        songId: s.songId,
        playCount: s.playCount,
        listenedMs: s.listenedMs,
        firstPlayedMs: s.firstPlayedMs,
        lastPlayedMs: s.lastPlayedMs,
        songTitle: s.songTitle,
        songArtist: s.songArtist,
        albumId: s.albumId,
        album: s.album,
        albumArtist: s.albumArtist,
      );

  void touch(int occurredAtMs) {
    firstPlayedMs = firstPlayedMs == null
        ? occurredAtMs
        : (occurredAtMs < firstPlayedMs! ? occurredAtMs : firstPlayedMs);
    lastPlayedMs = lastPlayedMs == null
        ? occurredAtMs
        : (occurredAtMs > lastPlayedMs! ? occurredAtMs : lastPlayedMs);
  }

  ListeningSongRollup toRollup() => ListeningSongRollup(
        songId: songId,
        playCount: playCount,
        listenedMs: listenedMs,
        firstPlayedMs: firstPlayedMs,
        lastPlayedMs: lastPlayedMs,
        songTitle: songTitle,
        songArtist: songArtist,
        albumId: albumId,
        album: album,
        albumArtist: albumArtist,
      );
}

class _MutableAlbum {
  final String albumKey;
  int playCount;
  int listenedMs;
  int? firstPlayedMs;
  int? lastPlayedMs;
  String? albumId;
  String? album;
  String? albumArtist;

  _MutableAlbum({
    required this.albumKey,
    this.playCount = 0,
    this.listenedMs = 0,
    this.firstPlayedMs,
    this.lastPlayedMs,
    this.albumId,
    this.album,
    this.albumArtist,
  });

  factory _MutableAlbum.from(ListeningAlbumRollup a) => _MutableAlbum(
        albumKey: a.albumKey,
        playCount: a.playCount,
        listenedMs: a.listenedMs,
        firstPlayedMs: a.firstPlayedMs,
        lastPlayedMs: a.lastPlayedMs,
        albumId: a.albumId,
        album: a.album,
        albumArtist: a.albumArtist,
      );

  void touch(int occurredAtMs) {
    firstPlayedMs = firstPlayedMs == null
        ? occurredAtMs
        : (occurredAtMs < firstPlayedMs! ? occurredAtMs : firstPlayedMs);
    lastPlayedMs = lastPlayedMs == null
        ? occurredAtMs
        : (occurredAtMs > lastPlayedMs! ? occurredAtMs : lastPlayedMs);
  }

  ListeningAlbumRollup toRollup() => ListeningAlbumRollup(
        albumKey: albumKey,
        albumId: albumId,
        album: album,
        albumArtist: albumArtist,
        playCount: playCount,
        listenedMs: listenedMs,
        firstPlayedMs: firstPlayedMs,
        lastPlayedMs: lastPlayedMs,
      );
}

class _MutableArtist {
  final String artistKey;
  int playCount;
  int listenedMs;
  int? firstPlayedMs;
  int? lastPlayedMs;
  String? artistDisplay;

  _MutableArtist({
    required this.artistKey,
    this.playCount = 0,
    this.listenedMs = 0,
    this.firstPlayedMs,
    this.lastPlayedMs,
    this.artistDisplay,
  });

  factory _MutableArtist.from(ListeningArtistRollup a) => _MutableArtist(
        artistKey: a.artistKey,
        playCount: a.playCount,
        listenedMs: a.listenedMs,
        firstPlayedMs: a.firstPlayedMs,
        lastPlayedMs: a.lastPlayedMs,
        artistDisplay: a.artistDisplay,
      );

  void touch(int occurredAtMs) {
    firstPlayedMs = firstPlayedMs == null
        ? occurredAtMs
        : (occurredAtMs < firstPlayedMs! ? occurredAtMs : firstPlayedMs);
    lastPlayedMs = lastPlayedMs == null
        ? occurredAtMs
        : (occurredAtMs > lastPlayedMs! ? occurredAtMs : lastPlayedMs);
  }

  ListeningArtistRollup toRollup() => ListeningArtistRollup(
        artistKey: artistKey,
        artistDisplay: artistDisplay,
        playCount: playCount,
        listenedMs: listenedMs,
        firstPlayedMs: firstPlayedMs,
        lastPlayedMs: lastPlayedMs,
      );
}
