/// Shared contract types for the Spotify Extended Streaming History importer.
///
/// This file is the seam between the two halves of the importer and is written
/// deliberately small: the matcher (library_track_matcher.dart) and the
/// parser/event-builder (spotify_history_parser.dart / spotify_event_builder.dart)
/// both depend ONLY on the types here, so they can be built independently without
/// drifting apart.
library;

/// One song from the user's local Ariami library, in the neutral shape the
/// matcher indexes. Clients map their own catalog model onto this (e.g. desktop
/// `SongModel` -> [LibraryCatalogEntry]) so core stays UI-agnostic.
class LibraryCatalogEntry {
  /// The Ariami song id (`md5(filePath)[:12]`). This is what a matched
  /// [ListeningEvent.songId] must carry so play counts land on the real song.
  final String songId;

  /// Raw title/artist/album tags exactly as stored in the library. The matcher
  /// normalizes internally; callers pass them verbatim.
  final String title;
  final String artist;
  final String? album;
  final String? albumId;
  final int? durationMs;

  const LibraryCatalogEntry({
    required this.songId,
    required this.title,
    required this.artist,
    this.album,
    this.albumId,
    this.durationMs,
  });
}

/// The Spotify-side identity a play is matched on: track title + album artist +
/// album name (the export carries no track-artist field and no album id).
///
/// Value equality + [hashCode] are defined so a large play list collapses to the
/// unique set of keys before matching (~7k keys for ~200k plays).
class SpotifyTrackKey {
  /// `master_metadata_track_name`.
  final String title;

  /// `master_metadata_album_artist_name` (album artist, NOT track artist).
  final String albumArtist;

  /// `master_metadata_album_album_name`, may be null/empty.
  final String? album;

  const SpotifyTrackKey({
    required this.title,
    required this.albumArtist,
    this.album,
  });

  @override
  bool operator ==(Object other) =>
      other is SpotifyTrackKey &&
      other.title == title &&
      other.albumArtist == albumArtist &&
      other.album == album;

  @override
  int get hashCode => Object.hash(title, albumArtist, album);

  @override
  String toString() => 'SpotifyTrackKey($title / $albumArtist / $album)';
}

/// How a [TrackMatch] was resolved, best confidence first.
enum MatchTier {
  /// Exact normalized title+artist key.
  exact,

  /// Matched by title+album agreement (artist string drifted).
  albumAnchored,

  /// Restricted fuzzy match above the auto-accept threshold.
  fuzzy,

  /// Multiple plausible candidates; [TrackMatch.songId] holds the best guess
  /// and [TrackMatch.alternateSongIds] the rest — surface for manual review.
  ambiguous,

  /// No library song matched. [TrackMatch.songId] is null.
  unmatched,
}

/// The result of matching one [SpotifyTrackKey] against the library.
///
/// CRITICAL for stats aggregation: when [songId] is non-null, [title]/[artist]/
/// [album]/[albumId] MUST be the LIBRARY's strings, not Spotify's. This is what
/// makes every imported play of e.g. "Beyoncé" (Spotify) roll up together with
/// live-tracked plays of the library artist "Beyonce" instead of fragmenting the
/// artist/song rollups. When [songId] is null, carry the Spotify strings so the
/// unmatched play still shows sensible metadata.
class TrackMatch {
  /// Library song id, or null when unmatched.
  final String? songId;

  final String title;
  final String artist;
  final String? album;
  final String? albumId;

  /// 0.0..1.0. 1.0 for exact; lower for fuzzy; 0.0 for unmatched.
  final double confidence;
  final MatchTier tier;

  /// Other candidate song ids when [tier] is [MatchTier.ambiguous].
  final List<String> alternateSongIds;

  const TrackMatch({
    required this.songId,
    required this.title,
    required this.artist,
    this.album,
    this.albumId,
    required this.confidence,
    required this.tier,
    this.alternateSongIds = const <String>[],
  });

  bool get isMatched => songId != null;
}

/// The matcher interface the event pipeline depends on. The concrete
/// implementation is [LibraryTrackMatcher]; depending on this abstraction keeps
/// the parser/builder testable with a fake and decoupled from index internals.
abstract class TrackMatcher {
  /// Match a single key.
  TrackMatch match(SpotifyTrackKey key);

  /// Match many keys at once (dedupe upstream via [SpotifyTrackKey] equality).
  Map<SpotifyTrackKey, TrackMatch> matchAll(Iterable<SpotifyTrackKey> keys);
}
