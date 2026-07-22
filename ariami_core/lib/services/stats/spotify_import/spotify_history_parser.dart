import 'dart:convert';

import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';

/// Supplies the listener's local UTC offset in minutes for a UTC instant.
/// Core has no timezone database, so the caller injects this — DST-aware via
/// a real tz lookup, or a fixed offset.
typedef TzOffsetMinutesFor = int Function(int occurredAtUtcMillis);

/// One eligible music play extracted from a Spotify Extended Streaming
/// History record, carrying everything the event builder needs.
class SpotifyPlay {
  /// The identity the track matcher resolves against the library.
  final SpotifyTrackKey trackKey;

  /// `spotify_track_uri`; kept so unmatched plays get a stable synthetic id.
  final String trackUri;

  /// When the play happened, UTC epoch millis. For offline plays this is
  /// `offline_timestamp` (`ts` is the sync time for those and would poison
  /// daily rollups with impossible bursts).
  final int occurredAtMs;

  /// `ms_played` — full credited listening for this play.
  final int listenedMs;

  /// The listener's UTC offset at [occurredAtMs], from [TzOffsetMinutesFor].
  final int tzOffsetMinutes;

  /// Stable per-record identity
  /// (`ts|spotify_track_uri|ms_played|reason_end|offline_timestamp|platform`).
  /// `ts`+uri alone is not unique (offline replays share one sync second), so
  /// the full record is hashed — byte-identical export-artifact rows collapse,
  /// genuinely different replays stay distinct.
  final String rawIdentity;

  const SpotifyPlay({
    required this.trackKey,
    required this.trackUri,
    required this.occurredAtMs,
    required this.listenedMs,
    required this.tzOffsetMinutes,
    required this.rawIdentity,
  });
}

/// What the parser kept and dropped, for the import preview UI.
class SpotifyParseSummary {
  /// Records fed into the parser.
  final int totalRecords;

  /// Records kept as plays.
  final int eligiblePlays;

  /// Music records dropped by the play rule
  /// (`ms_played >= 30000 OR (reason_end == 'trackdone' AND ms_played > 0)`).
  final int droppedByPlayRule;

  /// Podcast records (`spotify_episode_uri != null`).
  final int podcastsExcluded;

  /// Audiobook records (any `audiobook_*` field non-null).
  final int audiobooksExcluded;

  /// Records without a usable track identity (null `spotify_track_uri` or
  /// `master_metadata_track_name`), or with an unparseable timestamp.
  final int missingTrackExcluded;

  /// Private-session plays dropped because `importIncognito` was false.
  final int incognitoExcluded;

  /// Eligible offline plays whose time was taken from `offline_timestamp`.
  final int offlineCorrected;

  const SpotifyParseSummary({
    required this.totalRecords,
    required this.eligiblePlays,
    required this.droppedByPlayRule,
    required this.podcastsExcluded,
    required this.audiobooksExcluded,
    required this.missingTrackExcluded,
    required this.incognitoExcluded,
    required this.offlineCorrected,
  });

  int get totalDropped => totalRecords - eligiblePlays;
}

/// The parser's output: the eligible plays plus the drop/keep accounting.
class SpotifyParseResult {
  final List<SpotifyPlay> plays;
  final SpotifyParseSummary summary;

  const SpotifyParseResult({required this.plays, required this.summary});
}

/// Extracts eligible music plays from decoded Spotify Extended Streaming
/// History records. Pure and IO-free: the caller reads/decodes the export
/// files (and simply never feeds in the `*_Video_*` files).
class SpotifyHistoryParser {
  const SpotifyHistoryParser();

  /// Spotify's 30-second stream definition, same as Ariami's tracker rule.
  static const int minPlayedMs = 30000;

  /// `reason_end` value meaning the track played to natural completion.
  static const String trackDoneReason = 'trackdone';

  /// Parse already-decoded records (one per JSON array entry).
  SpotifyParseResult parse(
    List<Map<String, dynamic>> records, {
    required TzOffsetMinutesFor tzOffsetMinutesFor,
    bool importIncognito = false,
  }) {
    final plays = <SpotifyPlay>[];
    var droppedByPlayRule = 0;
    var podcasts = 0;
    var audiobooks = 0;
    var missingTrack = 0;
    var incognito = 0;
    var offlineCorrected = 0;

    for (final record in records) {
      if (record['spotify_episode_uri'] != null) {
        podcasts++;
        continue;
      }
      if (_hasAudiobookMetadata(record)) {
        audiobooks++;
        continue;
      }
      final trackUri = record['spotify_track_uri'];
      final trackName = record['master_metadata_track_name'];
      if (trackUri is! String ||
          trackUri.isEmpty ||
          trackName is! String ||
          trackName.isEmpty) {
        missingTrack++;
        continue;
      }
      if (!importIncognito && record['incognito_mode'] == true) {
        incognito++;
        continue;
      }

      final msPlayedValue = record['ms_played'];
      final msPlayed = msPlayedValue is num ? msPlayedValue.toInt() : 0;
      final trackDone = record['reason_end'] == trackDoneReason;
      if (!(msPlayed >= minPlayedMs || (trackDone && msPlayed > 0))) {
        droppedByPlayRule++;
        continue;
      }

      // Offline plays: `ts` is the sync time, not the play time — up to 185
      // records share one second. Use offline_timestamp (epoch ms) instead.
      final offlineTimestamp = record['offline_timestamp'];
      int occurredAtMs;
      var usedOfflineTimestamp = false;
      if (record['offline'] == true &&
          offlineTimestamp is num &&
          offlineTimestamp > 0) {
        occurredAtMs = offlineTimestamp.toInt();
        usedOfflineTimestamp = true;
      } else {
        final ts = record['ts'];
        final parsed = ts is String ? DateTime.tryParse(ts) : null;
        if (parsed == null) {
          // Cannot be placed in time — unusable.
          missingTrack++;
          continue;
        }
        occurredAtMs = parsed.toUtc().millisecondsSinceEpoch;
      }
      if (usedOfflineTimestamp) offlineCorrected++;

      final albumArtist = record['master_metadata_album_artist_name'];
      final album = record['master_metadata_album_album_name'];
      plays.add(SpotifyPlay(
        trackKey: SpotifyTrackKey(
          title: trackName,
          albumArtist: albumArtist is String ? albumArtist : '',
          album: album is String && album.isNotEmpty ? album : null,
        ),
        trackUri: trackUri,
        occurredAtMs: occurredAtMs,
        listenedMs: msPlayed,
        tzOffsetMinutes: tzOffsetMinutesFor(occurredAtMs),
        rawIdentity: _rawIdentity(record),
      ));
    }

    return SpotifyParseResult(
      plays: plays,
      summary: SpotifyParseSummary(
        totalRecords: records.length,
        eligiblePlays: plays.length,
        droppedByPlayRule: droppedByPlayRule,
        podcastsExcluded: podcasts,
        audiobooksExcluded: audiobooks,
        missingTrackExcluded: missingTrack,
        incognitoExcluded: incognito,
        offlineCorrected: offlineCorrected,
      ),
    );
  }

  /// Convenience for callers holding a raw export file's contents: decode,
  /// then delegate to [parse].
  SpotifyParseResult parseJsonString(
    String jsonString, {
    required TzOffsetMinutesFor tzOffsetMinutesFor,
    bool importIncognito = false,
  }) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      throw const FormatException(
        'Spotify history export must be a JSON array of records',
      );
    }
    return parse(
      decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList(),
      tzOffsetMinutesFor: tzOffsetMinutesFor,
      importIncognito: importIncognito,
    );
  }

  static bool _hasAudiobookMetadata(Map<String, dynamic> record) {
    for (final entry in record.entries) {
      if (entry.key.startsWith('audiobook_') && entry.value != null) {
        return true;
      }
    }
    return false;
  }

  /// The idempotency identity: the full record, so byte-identical artifact
  /// rows collapse while distinct offline replays (same sync `ts`, different
  /// `offline_timestamp`/`ms_played`) stay distinct.
  static String _rawIdentity(Map<String, dynamic> record) => <Object?>[
        record['ts'],
        record['spotify_track_uri'],
        record['ms_played'],
        record['reason_end'],
        record['offline_timestamp'],
        record['platform'],
      ].join('|');
}
