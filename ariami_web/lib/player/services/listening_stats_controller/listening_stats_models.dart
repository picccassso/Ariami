part of '../listening_stats_controller.dart';

/// Account-wide listening data shaped for the desktop Settings experience.
///
/// Songs retain the shared core model. Artists and albums prefer the
/// server's own rollups when provided — artists are then *credited* artists
/// (multi-artist strings split server-side, so a play of "Mercy" counts
/// under each collaborator individually). Without server rollups (old
/// server, offline) they are derived from the songs exactly like before.
class ListeningStatsSnapshot {
  const ListeningStatsSnapshot({
    required this.songs,
    required this.artists,
    required this.albums,
    required this.totalListenedMs,
    required this.totalPlays,
    required this.averageDailyMs,
  });

  factory ListeningStatsSnapshot.fromSongs(
    Iterable<ListeningSongRollup> source, {
    List<ListeningArtistRollup> creditedArtists =
        const <ListeningArtistRollup>[],
    List<ListeningAlbumRollup> serverAlbums = const <ListeningAlbumRollup>[],
    Map<String, Album> albumCatalog = const <String, Album>{},
    int activeDays = 0,
  }) {
    final songs = source
        .where((song) => song.playCount > 0)
        .map((song) =>
            _enrichSongRollup(_sanitizeSongRollup(song), albumCatalog))
        .toList()
      ..sort((a, b) {
        final byPlays = b.playCount.compareTo(a.playCount);
        return byPlays != 0 ? byPlays : b.listenedMs.compareTo(a.listenedMs);
      });

    final artistBuilders = <String, _ArtistStatsBuilder>{};
    final albumBuilders = <String, _AlbumStatsBuilder>{};
    var totalListenedMs = 0;
    var totalPlays = 0;
    int? firstPlayedMs;
    int? lastPlayedMs;

    for (final song in songs) {
      totalListenedMs += song.listenedMs;
      totalPlays += song.playCount;
      if (song.firstPlayedMs != null &&
          (firstPlayedMs == null || song.firstPlayedMs! < firstPlayedMs)) {
        firstPlayedMs = song.firstPlayedMs;
      }
      if (song.lastPlayedMs != null &&
          (lastPlayedMs == null || song.lastPlayedMs! > lastPlayedMs)) {
        lastPlayedMs = song.lastPlayedMs;
      }

      final artistName = _cleanArtistName(
        song.albumArtist ?? song.songArtist ?? 'Unknown Artist',
      );
      final artistKey = _normalizeArtistKey(artistName);
      final artist = artistBuilders.putIfAbsent(
        artistKey,
        () => _ArtistStatsBuilder(name: artistName),
      );
      artist.add(song, displayName: artistName);

      final albumId = song.albumId;
      if (albumId != null && albumId.isNotEmpty) {
        albumBuilders
            .putIfAbsent(
              albumId,
              () => _AlbumStatsBuilder(
                albumId: albumId,
                title: song.album ?? 'Unknown Album',
                artist: song.albumArtist ?? song.songArtist ?? 'Unknown Artist',
              ),
            )
            .add(song);
      }
    }

    // Server rollups arrive sorted by listened time; the derived fallbacks
    // sort themselves the same way.
    final artists = creditedArtists.isNotEmpty
        ? creditedArtistStats(creditedArtists, songs)
        : (artistBuilders.values.map((value) => value.build()).toList()
          ..sort((a, b) => b.listenedMs.compareTo(a.listenedMs)));
    final albums = serverAlbums.isNotEmpty
        ? serverAlbumStats(serverAlbums, albumCatalog: albumCatalog)
        : (albumBuilders.values.map((value) => value.build()).toList()
          ..sort((a, b) => b.listenedMs.compareTo(a.listenedMs)));

    // Prefer the server's count of distinct listening days: a "per active
    // day" average is more meaningful and immune to a single stray timestamp
    // stretching the span. Fall back to the first-to-last calendar span only
    // when the count is unavailable (older servers report 0).
    var averageDailyMs = 0;
    if (activeDays > 0) {
      averageDailyMs = totalListenedMs ~/ activeDays;
    } else if (firstPlayedMs != null && lastPlayedMs != null) {
      final first = DateTime.fromMillisecondsSinceEpoch(firstPlayedMs);
      final last = DateTime.fromMillisecondsSinceEpoch(lastPlayedMs);
      final calendarDays = last.difference(first).inDays + 1;
      if (calendarDays > 0) averageDailyMs = totalListenedMs ~/ calendarDays;
    }

    return ListeningStatsSnapshot(
      songs: List.unmodifiable(songs),
      artists: List.unmodifiable(artists),
      albums: List.unmodifiable(albums),
      totalListenedMs: totalListenedMs,
      totalPlays: totalPlays,
      averageDailyMs: averageDailyMs,
    );
  }

  final List<ListeningSongRollup> songs;
  final List<ListeningArtistStat> artists;
  final List<ListeningAlbumStat> albums;
  final int totalListenedMs;
  final int totalPlays;
  final int averageDailyMs;

  static const empty = ListeningStatsSnapshot(
    songs: <ListeningSongRollup>[],
    artists: <ListeningArtistStat>[],
    albums: <ListeningAlbumStat>[],
    totalListenedMs: 0,
    totalPlays: 0,
    averageDailyMs: 0,
  );
}

/// Desktop display model for one artist row (distinct from the core wire
/// model [ListeningArtistRollup]).
class ListeningArtistStat {
  const ListeningArtistStat({
    required this.name,
    required this.playCount,
    required this.listenedMs,
    required this.uniqueSongs,
    this.artworkAlbumId,
    this.artworkSongId,
  });

  final String name;
  final int playCount;
  final int listenedMs;
  final int uniqueSongs;
  final String? artworkAlbumId;
  final String? artworkSongId;
}

/// Desktop display model for one album row (distinct from the core wire
/// model [ListeningAlbumRollup]).
class ListeningAlbumStat {
  const ListeningAlbumStat({
    required this.albumId,
    required this.title,
    required this.artist,
    required this.playCount,
    required this.listenedMs,
    required this.uniqueSongs,
  });

  final String albumId;
  final String title;
  final String artist;
  final int playCount;
  final int listenedMs;
  final int uniqueSongs;
}

class _ArtistStatsBuilder {
  _ArtistStatsBuilder({required this.name});

  String name;
  int playCount = 0;
  int listenedMs = 0;
  int uniqueSongs = 0;
  int _displayNamePlays = 0;
  String? artworkAlbumId;
  String? artworkSongId;

  void add(ListeningSongRollup song, {required String displayName}) {
    playCount += song.playCount;
    listenedMs += song.listenedMs;
    uniqueSongs++;
    artworkAlbumId ??= song.albumId;
    if (song.albumId == null || song.albumId!.isEmpty) {
      artworkSongId ??= song.songId;
    }
    if (song.playCount > _displayNamePlays) {
      name = displayName;
      _displayNamePlays = song.playCount;
    }
  }

  ListeningArtistStat build() => ListeningArtistStat(
        name: name,
        playCount: playCount,
        listenedMs: listenedMs,
        uniqueSongs: uniqueSongs,
        artworkAlbumId: artworkAlbumId,
        artworkSongId: artworkSongId,
      );
}

class _AlbumStatsBuilder {
  _AlbumStatsBuilder({
    required this.albumId,
    required this.title,
    required this.artist,
  });

  final String albumId;
  final String title;
  final String artist;
  int playCount = 0;
  int listenedMs = 0;
  int uniqueSongs = 0;

  void add(ListeningSongRollup song) {
    playCount += song.playCount;
    listenedMs += song.listenedMs;
    uniqueSongs++;
  }

  ListeningAlbumStat build() => ListeningAlbumStat(
        albumId: albumId,
        title: title,
        artist: artist,
        playCount: playCount,
        listenedMs: listenedMs,
        uniqueSongs: uniqueSongs,
      );
}

/// Adapts server credited-artist rollups to the desktop display model.
///
/// Artwork and per-artist song counts aren't part of the rollup, so they are
/// recovered by matching the credited name back against the songs' combined
/// artist strings (which is where the credit came from).
List<ListeningArtistStat> creditedArtistStats(
  List<ListeningArtistRollup> credited,
  List<ListeningSongRollup> songs,
) {
  // The scan is O(artists × songs); lower each song's combined artist string
  // once here rather than once per artist, which dominated the cost on large
  // uncapped lists.
  final haystacks = List<String>.generate(
    songs.length,
    (i) =>
        '${songs[i].songArtist ?? ''}\n${songs[i].albumArtist ?? ''}'
            .toLowerCase(),
    growable: false,
  );
  final stats = <ListeningArtistStat>[];
  for (final rollup in credited) {
    if (rollup.playCount <= 0 && rollup.listenedMs <= 0) continue;
    final display = _sanitizeOptionalTag(rollup.artistDisplay) ??
        _sanitizeOptionalTag(rollup.artistKey) ??
        'Unknown Artist';
    final needle = display.toLowerCase();
    String? artworkAlbumId;
    String? artworkSongId;
    var uniqueSongs = 0;
    for (var i = 0; i < songs.length; i++) {
      if (!haystacks[i].contains(needle)) continue;
      final song = songs[i];
      uniqueSongs++;
      artworkAlbumId ??= song.albumId;
      if (song.albumId == null || song.albumId!.isEmpty) {
        artworkSongId ??= song.songId;
      }
    }
    stats.add(ListeningArtistStat(
      name: display,
      playCount: rollup.playCount,
      listenedMs: rollup.listenedMs,
      uniqueSongs: uniqueSongs,
      artworkAlbumId: artworkAlbumId,
      artworkSongId: artworkSongId,
    ));
  }
  return stats;
}

/// Adapts server album rollups to the desktop display model. Rollups keyed
/// only by a normalized name (no catalog albumId) keep an empty id, which
/// display code must treat as "no artwork". Song counts aren't part of the
/// rollup, so [ListeningAlbumStat.uniqueSongs] is 0.
List<ListeningAlbumStat> serverAlbumStats(
  List<ListeningAlbumRollup> rollups, {
  Map<String, Album> albumCatalog = const <String, Album>{},
}) {
  return [
    for (final rollup in rollups)
      if (rollup.playCount > 0 || rollup.listenedMs > 0)
        ListeningAlbumStat(
          albumId: rollup.albumId ?? '',
          title: _sanitizeOptionalTag(rollup.album) ??
              albumCatalog[rollup.albumId]?.title ??
              'Unknown Album',
          artist: _sanitizeOptionalTag(rollup.albumArtist) ??
              albumCatalog[rollup.albumId]?.artist ??
              'Unknown Artist',
          playCount: rollup.playCount,
          listenedMs: rollup.listenedMs,
          uniqueSongs: 0,
        ),
  ];
}

ListeningSongRollup _enrichSongRollup(
  ListeningSongRollup song,
  Map<String, Album> albumCatalog,
) {
  final album = albumCatalog[song.albumId];
  if (album == null) return song;
  return ListeningSongRollup(
    songId: song.songId,
    playCount: song.playCount,
    listenedMs: song.listenedMs,
    firstPlayedMs: song.firstPlayedMs,
    lastPlayedMs: song.lastPlayedMs,
    songTitle: song.songTitle,
    songArtist: song.songArtist,
    albumId: song.albumId,
    album: _sanitizeOptionalTag(song.album) ?? album.title,
    albumArtist: _sanitizeOptionalTag(song.albumArtist) ?? album.artist,
  );
}

ListeningSongRollup _sanitizeSongRollup(ListeningSongRollup song) =>
    ListeningSongRollup(
      songId: song.songId,
      playCount: song.playCount,
      listenedMs: song.listenedMs,
      firstPlayedMs: song.firstPlayedMs,
      lastPlayedMs: song.lastPlayedMs,
      songTitle: _sanitizeOptionalTag(song.songTitle),
      songArtist: _sanitizeOptionalTag(song.songArtist),
      albumId: song.albumId,
      album: _sanitizeOptionalTag(song.album),
      albumArtist: _sanitizeOptionalTag(song.albumArtist),
    );

String? _sanitizeOptionalTag(String? value) {
  if (value == null) return null;
  final sanitized = sanitizeTagText(value);
  return sanitized.isEmpty ? null : sanitized;
}

String _cleanArtistName(String name) => sanitizeTagText(name);

String _normalizeArtistKey(String name) => _cleanArtistName(name)
    .toLowerCase()
    .replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ');

class PlayEvent {
  final DateTime timestamp;
  final String artist;
  final String title;

  const PlayEvent({
    required this.timestamp,
    required this.artist,
    required this.title,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ts': timestamp.millisecondsSinceEpoch,
        'artist': artist,
        'title': title,
      };

  factory PlayEvent.fromJson(Map<String, dynamic> json) => PlayEvent(
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int? ?? 0),
        artist: json['artist'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );
}
