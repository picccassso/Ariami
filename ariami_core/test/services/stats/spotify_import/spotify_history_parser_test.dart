import 'dart:convert';

import 'package:ariami_core/services/stats/spotify_import/spotify_history_parser.dart';
import 'package:test/test.dart';

void main() {
  const parser = SpotifyHistoryParser();

  int fixedTzOffset(int _) => 60;

  Map<String, dynamic> record({
    String? ts = '2021-03-14T01:23:45Z',
    String? trackUri = 'spotify:track:4uLU6hMCjMI75M1A2tKUQC',
    String? trackName = 'The Song',
    String? albumArtist = 'The Artist',
    String? album = 'The Album',
    int msPlayed = 45000,
    String? reasonEnd = 'trackdone',
    bool? offline,
    int? offlineTimestamp,
    String? platform = 'ios',
    bool incognito = false,
    String? episodeUri,
    String? audiobookTitle,
  }) =>
      <String, dynamic>{
        'ts': ts,
        'platform': platform,
        'ms_played': msPlayed,
        'conn_country': 'GB',
        'master_metadata_track_name': trackName,
        'master_metadata_album_artist_name': albumArtist,
        'master_metadata_album_album_name': album,
        'spotify_track_uri': trackUri,
        'spotify_episode_uri': episodeUri,
        'audiobook_title': audiobookTitle,
        'audiobook_uri': null,
        'reason_end': reasonEnd,
        'offline': offline,
        'offline_timestamp': offlineTimestamp,
        'incognito_mode': incognito,
      };

  SpotifyParseResult parse(
    List<Map<String, dynamic>> records, {
    TzOffsetMinutesFor? tzOffsetMinutesFor,
    bool importIncognito = false,
  }) =>
      parser.parse(
        records,
        tzOffsetMinutesFor: tzOffsetMinutesFor ?? fixedTzOffset,
        importIncognito: importIncognito,
      );

  group('eligibility (play rule)', () {
    test('keeps a record at exactly 30s', () {
      final result = parse([record(msPlayed: 30000, reasonEnd: 'clickrow')]);
      expect(result.plays, hasLength(1));
      expect(result.plays.single.listenedMs, 30000);
    });

    test('drops a record under 30s without trackdone', () {
      final result = parse([record(msPlayed: 29999, reasonEnd: 'clickrow')]);
      expect(result.plays, isEmpty);
      expect(result.summary.droppedByPlayRule, 1);
    });

    test('keeps a short record that played to completion', () {
      final result = parse([record(msPlayed: 500, reasonEnd: 'trackdone')]);
      expect(result.plays, hasLength(1));
    });

    test('drops a zero-ms record even with trackdone', () {
      final result = parse([record(msPlayed: 0, reasonEnd: 'trackdone')]);
      expect(result.plays, isEmpty);
      expect(result.summary.droppedByPlayRule, 1);
    });

    test('keeps a >= 30s record regardless of reason_end', () {
      final result = parse([record(msPlayed: 45000, reasonEnd: null)]);
      expect(result.plays, hasLength(1));
    });

    test('does not drop skipped plays that reached 30s', () {
      // `skipped` only means "ended by user action", not "barely heard".
      final skipped = record(msPlayed: 35000, reasonEnd: 'fwdbtn')
        ..['skipped'] = true;
      final result = parse([skipped]);
      expect(result.plays, hasLength(1));
    });
  });

  group('non-music filtering', () {
    test('drops podcast records', () {
      final result =
          parse([record(episodeUri: 'spotify:episode:abc123', trackUri: null)]);
      expect(result.plays, isEmpty);
      expect(result.summary.podcastsExcluded, 1);
    });

    test('drops audiobook records', () {
      final result = parse([record(audiobookTitle: 'Some Audiobook')]);
      expect(result.plays, isEmpty);
      expect(result.summary.audiobooksExcluded, 1);
    });

    test('drops records with a null track uri', () {
      final result = parse([record(trackUri: null)]);
      expect(result.plays, isEmpty);
      expect(result.summary.missingTrackExcluded, 1);
    });

    test('drops records with a null track name', () {
      final result = parse([record(trackName: null)]);
      expect(result.plays, isEmpty);
      expect(result.summary.missingTrackExcluded, 1);
    });
  });

  group('incognito', () {
    test('drops private-session plays by default', () {
      final result = parse([record(incognito: true)]);
      expect(result.plays, isEmpty);
      expect(result.summary.incognitoExcluded, 1);
    });

    test('keeps private-session plays when importIncognito is true', () {
      final result = parse([record(incognito: true)], importIncognito: true);
      expect(result.plays, hasLength(1));
      expect(result.summary.incognitoExcluded, 0);
    });
  });

  group('occurred-at', () {
    test('parses ts as ISO-8601 UTC epoch millis', () {
      final result = parse([record()]);
      expect(
        result.plays.single.occurredAtMs,
        DateTime.utc(2021, 3, 14, 1, 23, 45).millisecondsSinceEpoch,
      );
    });

    test('offline plays use offline_timestamp, not the sync ts', () {
      const offlineTs = 1609459200000; // 2021-01-01T00:00:00Z
      final result = parse([
        record(
          ts: '2021-03-14T01:23:45Z',
          offline: true,
          offlineTimestamp: offlineTs,
        ),
      ]);
      expect(result.plays.single.occurredAtMs, offlineTs);
      expect(result.summary.offlineCorrected, 1);
    });

    test('offline record without offline_timestamp falls back to ts', () {
      final result = parse([record(offline: true)]);
      expect(
        result.plays.single.occurredAtMs,
        DateTime.utc(2021, 3, 14, 1, 23, 45).millisecondsSinceEpoch,
      );
      expect(result.summary.offlineCorrected, 0);
    });

    test('offline == null is treated as false', () {
      final result = parse([record(offlineTimestamp: 1609459200000)]);
      expect(
        result.plays.single.occurredAtMs,
        DateTime.utc(2021, 3, 14, 1, 23, 45).millisecondsSinceEpoch,
      );
      expect(result.summary.offlineCorrected, 0);
    });

    test('drops records with an unparseable ts', () {
      final result = parse([record(ts: 'not-a-date')]);
      expect(result.plays, isEmpty);
      expect(result.summary.missingTrackExcluded, 1);
    });
  });

  group('timezone offset', () {
    test('stores the injected offset and queries it at occurredAt', () {
      final queriedAt = <int>[];
      final result = parse(
        [record()],
        tzOffsetMinutesFor: (occurredAtUtcMillis) {
          queriedAt.add(occurredAtUtcMillis);
          return -300;
        },
      );
      expect(result.plays.single.tzOffsetMinutes, -300);
      expect(queriedAt, [result.plays.single.occurredAtMs]);
    });
  });

  group('track key', () {
    test('carries title, album artist and album', () {
      final result = parse([record()]);
      final key = result.plays.single.trackKey;
      expect(key.title, 'The Song');
      expect(key.albumArtist, 'The Artist');
      expect(key.album, 'The Album');
    });

    test('tolerates missing album artist / album', () {
      final result = parse([record(albumArtist: null, album: null)]);
      final key = result.plays.single.trackKey;
      expect(key.albumArtist, '');
      expect(key.album, isNull);
    });
  });

  group('raw identity', () {
    test('is ts|uri|ms_played|reason_end|offline_timestamp|platform', () {
      final result = parse([
        record(
          offline: true,
          offlineTimestamp: 1609459200000,
          platform: 'android',
        ),
      ]);
      expect(
        result.plays.single.rawIdentity,
        '2021-03-14T01:23:45Z|spotify:track:4uLU6hMCjMI75M1A2tKUQC'
        '|45000|trackdone|1609459200000|android',
      );
    });

    test('byte-identical rows produce the same identity', () {
      final result = parse([record(), record()]);
      expect(result.plays, hasLength(2));
      expect(result.plays[0].rawIdentity, result.plays[1].rawIdentity);
    });

    test('offline replays sharing ts+uri stay distinct', () {
      final result = parse([
        record(offline: true, offlineTimestamp: 1609459200000),
        record(
          offline: true,
          offlineTimestamp: 1609545600000,
          msPlayed: 60000,
        ),
      ]);
      expect(result.plays, hasLength(2));
      expect(result.plays[0].rawIdentity, isNot(result.plays[1].rawIdentity));
    });
  });

  group('summary', () {
    test('accounts for every record exactly once', () {
      final result = parse([
        record(), // eligible
        record(
          ts: '2021-03-14T02:00:00Z',
          offline: true,
          offlineTimestamp: 1609459200000,
        ), // eligible, offline-corrected
        record(msPlayed: 100, reasonEnd: 'clickrow'), // play rule
        record(episodeUri: 'spotify:episode:x', trackUri: null), // podcast
        record(audiobookTitle: 'Audio Book'), // audiobook
        record(incognito: true), // incognito
        record(trackUri: null), // missing track identity
      ]);
      final summary = result.summary;
      expect(summary.totalRecords, 7);
      expect(summary.eligiblePlays, 2);
      expect(summary.droppedByPlayRule, 1);
      expect(summary.podcastsExcluded, 1);
      expect(summary.audiobooksExcluded, 1);
      expect(summary.incognitoExcluded, 1);
      expect(summary.missingTrackExcluded, 1);
      expect(summary.offlineCorrected, 1);
      expect(summary.totalDropped, 5);
      expect(result.plays, hasLength(2));
    });
  });

  group('parseJsonString', () {
    test('decodes a JSON array and delegates', () {
      final result = parser.parseJsonString(
        jsonEncode([record(), record(msPlayed: 10, reasonEnd: 'clickrow')]),
        tzOffsetMinutesFor: fixedTzOffset,
      );
      expect(result.summary.totalRecords, 2);
      expect(result.plays, hasLength(1));
    });

    test('throws FormatException for a non-array document', () {
      expect(
        () => parser.parseJsonString(
          '{"not": "an array"}',
          tzOffsetMinutesFor: fixedTzOffset,
        ),
        throwsFormatException,
      );
    });
  });
}
