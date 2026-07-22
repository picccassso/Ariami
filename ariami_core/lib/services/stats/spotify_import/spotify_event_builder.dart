import 'dart:convert';

import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_history_parser.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';
import 'package:crypto/crypto.dart';

/// Turns eligible [SpotifyPlay]s into idempotent [ListeningEvent]s.
///
/// One COMBINED event per play (`plays = 1`, `listenedMs = ms_played`,
/// `playId = null`). The eventId is deterministic
/// (`spotify:<userId>:sha256("v1" | rawIdentity)`), so re-imports and
/// overlapping exports are clean no-ops under the server's
/// `INSERT OR IGNORE` dedup; `userId` is in the id because the global
/// event_id primary key is not per-user.
class SpotifyEventBuilder {
  const SpotifyEventBuilder();

  /// [ListeningEvent.eventId] prefix; also the key for the selective-reset
  /// ("undo import") path on the server.
  static const String eventIdPrefix = 'spotify:';

  /// [ListeningEvent.sourceKind] for every imported event.
  static const String importSourceKind = 'import';

  /// Build the single combined event for one play. [match] carries LIBRARY
  /// strings when matched (never overwrite them with Spotify's — that is
  /// what keeps repeated plays aggregating with live-tracked ones).
  ListeningEvent build(
    SpotifyPlay play,
    TrackMatch match, {
    required String userId,
    required String clientKind,
  }) {
    final digest = sha256.convert(utf8.encode('v1|${play.rawIdentity}'));
    return ListeningEvent(
      eventId: '$eventIdPrefix$userId:$digest',
      songId: match.songId ?? syntheticSongIdFor(play.trackUri),
      listenedMs: play.listenedMs,
      plays: 1,
      occurredAtMs: play.occurredAtMs,
      tzOffsetMinutes: play.tzOffsetMinutes,
      songTitle: match.title,
      songArtist: match.artist,
      albumId: match.albumId,
      album: match.album,
      // No albumArtist: TrackMatch intentionally carries no library album
      // artist, and importing Spotify's would fragment artist rollups.
      sourceKind: importSourceKind,
      clientKind: clientKind,
    );
  }

  /// Build events for a whole play list. Keys missing from [matches] are
  /// treated as unmatched (synthetic id, Spotify strings).
  List<ListeningEvent> buildAll(
    Iterable<SpotifyPlay> plays,
    Map<SpotifyTrackKey, TrackMatch> matches, {
    required String userId,
    required String clientKind,
  }) {
    return <ListeningEvent>[
      for (final play in plays)
        build(
          play,
          matches[play.trackKey] ?? unmatchedMatchFor(play.trackKey),
          userId: userId,
          clientKind: clientKind,
        ),
    ];
  }

  /// Stable song id for unmatched tracks (`spotify-uri:<base62 id>`): the
  /// play still counts in stats, it just isn't playable or artwork-linked.
  static String syntheticSongIdFor(String trackUri) {
    const prefix = 'spotify:track:';
    final id = trackUri.startsWith(prefix)
        ? trackUri.substring(prefix.length)
        : trackUri;
    final songId = 'spotify-uri:$id';
    // Server bound: songId <= 256 chars.
    return songId.length <= 256 ? songId : songId.substring(0, 256);
  }

  /// The [TrackMatch] for a key the matcher could not resolve: carries the
  /// Spotify strings so the play still shows sensible metadata.
  static TrackMatch unmatchedMatchFor(SpotifyTrackKey key) => TrackMatch(
        songId: null,
        title: key.title,
        artist: key.albumArtist,
        album: key.album,
        confidence: 0.0,
        tier: MatchTier.unmatched,
      );
}
