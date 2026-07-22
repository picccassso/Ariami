import 'dart:convert';

import 'package:ariami_core/services/stats/spotify_import/spotify_event_builder.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_history_parser.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_importer.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  const builder = SpotifyEventBuilder();

  const key = SpotifyTrackKey(
    title: 'Spotify Song',
    albumArtist: 'Spotify Artist',
    album: 'Spotify Album',
  );

  const matched = TrackMatch(
    songId: 'abc123def456',
    title: 'Library Song',
    artist: 'Library Artist',
    album: 'Library Album',
    albumId: 'lib-album-1',
    confidence: 1.0,
    tier: MatchTier.exact,
  );

  const unmatched = TrackMatch(
    songId: null,
    title: 'Spotify Song',
    artist: 'Spotify Artist',
    album: 'Spotify Album',
    confidence: 0.0,
    tier: MatchTier.unmatched,
  );

  SpotifyPlay play({
    SpotifyTrackKey trackKey = key,
    String trackUri = 'spotify:track:4uLU6hMCjMI75M1A2tKUQC',
    int occurredAtMs = 1615685025000,
    int listenedMs = 45000,
    int tzOffsetMinutes = 60,
    String rawIdentity =
        '2021-03-14T01:23:45Z|spotify:track:4uLU6hMCjMI75M1A2tKUQC'
        '|45000|trackdone|null|ios',
  }) =>
      SpotifyPlay(
        trackKey: trackKey,
        trackUri: trackUri,
        occurredAtMs: occurredAtMs,
        listenedMs: listenedMs,
        tzOffsetMinutes: tzOffsetMinutes,
        rawIdentity: rawIdentity,
      );

  group('build', () {
    test('builds one combined event per play', () {
      final event = builder.build(
        play(),
        matched,
        userId: 'user1',
        clientKind: 'desktop',
      );
      expect(event.plays, 1);
      expect(event.listenedMs, 45000);
      expect(event.playId, isNull);
      expect(event.occurredAtMs, 1615685025000);
      expect(event.tzOffsetMinutes, 60);
      expect(event.sourceKind, 'import');
      expect(event.clientKind, 'desktop');
      expect(event.songDurationMs, isNull);
    });

    test('eventId follows the reconciled scheme', () {
      final p = play();
      final event = builder.build(
        p,
        matched,
        userId: 'user1',
        clientKind: 'desktop',
      );
      final expectedDigest =
          sha256.convert(utf8.encode('v1|${p.rawIdentity}'));
      expect(event.eventId, 'spotify:user1:$expectedDigest');
    });

    test('matched plays carry the library strings and song id', () {
      final event = builder.build(
        play(),
        matched,
        userId: 'user1',
        clientKind: 'desktop',
      );
      expect(event.songId, 'abc123def456');
      expect(event.songTitle, 'Library Song');
      expect(event.songArtist, 'Library Artist');
      expect(event.album, 'Library Album');
      expect(event.albumId, 'lib-album-1');
    });

    test('unmatched plays get a stable synthetic song id', () {
      final event = builder.build(
        play(),
        unmatched,
        userId: 'user1',
        clientKind: 'desktop',
      );
      expect(event.songId, 'spotify-uri:4uLU6hMCjMI75M1A2tKUQC');
      // ...and keep the Spotify strings so the play still shows metadata.
      expect(event.songTitle, 'Spotify Song');
      expect(event.songArtist, 'Spotify Artist');
      expect(event.album, 'Spotify Album');
    });

    test('synthetic id keeps non-standard uris verbatim (bounded)', () {
      expect(
        SpotifyEventBuilder.syntheticSongIdFor('spotify:local:whatever'),
        'spotify-uri:spotify:local:whatever',
      );
      final longUri = 'spotify:track:${'x' * 300}';
      expect(
        SpotifyEventBuilder.syntheticSongIdFor(longUri).length,
        lessThanOrEqualTo(256),
      );
    });
  });

  group('idempotency', () {
    test('same play built twice yields identical eventIds', () {
      final p = play();
      final a = builder.build(p, matched, userId: 'u', clientKind: 'desktop');
      final b = const SpotifyEventBuilder()
          .build(p, matched, userId: 'u', clientKind: 'desktop');
      expect(a.eventId, b.eventId);
    });

    test('byte-identical duplicate rows collapse to one id', () {
      final a = builder.build(play(), matched,
          userId: 'u', clientKind: 'desktop');
      final b = builder.build(play(), matched,
          userId: 'u', clientKind: 'desktop');
      expect(a.eventId, b.eventId);
    });

    test('offline replays sharing ts+uri but differing elsewhere differ', () {
      final a = builder.build(
        play(
          rawIdentity:
              '2021-03-14T01:23:45Z|spotify:track:4uLU6hMCjMI75M1A2tKUQC'
              '|45000|trackdone|1609459200000|ios',
        ),
        matched,
        userId: 'u',
        clientKind: 'desktop',
      );
      final b = builder.build(
        play(
          rawIdentity:
              '2021-03-14T01:23:45Z|spotify:track:4uLU6hMCjMI75M1A2tKUQC'
              '|60000|trackdone|1609545600000|ios',
        ),
        matched,
        userId: 'u',
        clientKind: 'desktop',
      );
      expect(a.eventId, isNot(b.eventId));
    });

    test('eventId is per-user (the primary key is global)', () {
      final p = play();
      final a = builder.build(p, matched, userId: 'u1', clientKind: 'desktop');
      final b = builder.build(p, matched, userId: 'u2', clientKind: 'desktop');
      expect(a.eventId, isNot(b.eventId));
    });
  });

  group('buildAll', () {
    test('falls back to unmatched for keys missing from the match map', () {
      final events = builder.buildAll(
        [play()],
        const <SpotifyTrackKey, TrackMatch>{},
        userId: 'u',
        clientKind: 'desktop',
      );
      expect(events, hasLength(1));
      expect(events.single.songId, 'spotify-uri:4uLU6hMCjMI75M1A2tKUQC');
      expect(events.single.songTitle, 'Spotify Song');
    });
  });

  group('SpotifyImporter (fake matcher)', () {
    const parser = SpotifyHistoryParser();

    Map<String, dynamic> record({
      String ts = '2021-03-14T01:23:45Z',
      String trackUri = 'spotify:track:4uLU6hMCjMI75M1A2tKUQC',
      String trackName = 'Spotify Song',
      String albumArtist = 'Spotify Artist',
      int msPlayed = 45000,
      String? reasonEnd = 'trackdone',
    }) =>
        <String, dynamic>{
          'ts': ts,
          'platform': 'ios',
          'ms_played': msPlayed,
          'master_metadata_track_name': trackName,
          'master_metadata_album_artist_name': albumArtist,
          'master_metadata_album_album_name': 'Spotify Album',
          'spotify_track_uri': trackUri,
          'reason_end': reasonEnd,
          'offline': null,
          'offline_timestamp': null,
          'incognito_mode': false,
        };

    test('parse -> match -> build, with match rates', () async {
      // Two plays of a matched track, one play of an unmatched track, and
      // one ineligible record.
      final records = [
        record(),
        record(ts: '2021-03-14T02:00:00Z'),
        record(
          ts: '2021-03-14T03:00:00Z',
          trackUri: 'spotify:track:OTHERTRACKID0000001',
          trackName: 'Unknown Song',
          albumArtist: 'Unknown Artist',
        ),
        record(ts: '2021-03-14T04:00:00Z', msPlayed: 10, reasonEnd: 'clickrow'),
      ];

      final result = await const SpotifyImporter().run(
        records: records,
        matcher: _FakeTrackMatcher({key: matched}),
        tzOffsetMinutesFor: (_) => 60,
        userId: 'user1',
        clientKind: 'desktop',
      );

      expect(result.events, hasLength(3));
      expect(result.summary.eligiblePlays, 3);
      expect(result.summary.droppedByPlayRule, 1);

      final matchedEvents =
          result.events.where((e) => e.songId == 'abc123def456');
      expect(matchedEvents, hasLength(2));
      expect(matchedEvents.every((e) => e.songTitle == 'Library Song'), isTrue);
      expect(
        result.events.any((e) => e.songId == 'spotify-uri:OTHERTRACKID0000001'),
        isTrue,
      );

      expect(result.trackMatchRate, closeTo(0.5, 1e-9));
      expect(result.playMatchRate, closeTo(2 / 3, 1e-9));
    });

    test('re-running the same records reproduces identical eventIds', () async {
      final records = [record(), record(ts: '2021-03-14T02:00:00Z')];
      const importer = SpotifyImporter();
      final first = await importer.run(
        records: records,
        matcher: _FakeTrackMatcher({key: matched}),
        tzOffsetMinutesFor: (_) => 0,
        userId: 'user1',
        clientKind: 'desktop',
      );
      final second = await importer.run(
        records: records,
        matcher: _FakeTrackMatcher({key: matched}),
        tzOffsetMinutesFor: (_) => 0,
        userId: 'user1',
        clientKind: 'desktop',
      );
      expect(
        first.events.map((e) => e.eventId).toList(),
        second.events.map((e) => e.eventId).toList(),
      );
    });

    test('empty input yields zero rates and no events', () async {
      final result = await const SpotifyImporter().run(
        records: const [],
        matcher: _FakeTrackMatcher(const {}),
        tzOffsetMinutesFor: (_) => 0,
        userId: 'user1',
        clientKind: 'desktop',
      );
      expect(result.events, isEmpty);
      expect(result.summary.totalRecords, 0);
      expect(result.trackMatchRate, 0.0);
      expect(result.playMatchRate, 0.0);
    });

    test('parser and importer share the same play interpretation', () {
      // Sanity: the facade really is parser -> matcher -> builder.
      final parsed = parser.parse(
        [record()],
        tzOffsetMinutesFor: (_) => 60,
      );
      final event = builder.build(
        parsed.plays.single,
        matched,
        userId: 'user1',
        clientKind: 'desktop',
      );
      expect(event.occurredAtMs, parsed.plays.single.occurredAtMs);
      expect(event.listenedMs, parsed.plays.single.listenedMs);
    });
  });
}

class _FakeTrackMatcher implements TrackMatcher {
  _FakeTrackMatcher(this._matches);

  final Map<SpotifyTrackKey, TrackMatch> _matches;

  @override
  TrackMatch match(SpotifyTrackKey key) =>
      _matches[key] ?? SpotifyEventBuilder.unmatchedMatchFor(key);

  @override
  Map<SpotifyTrackKey, TrackMatch> matchAll(Iterable<SpotifyTrackKey> keys) =>
      <SpotifyTrackKey, TrackMatch>{for (final key in keys) key: match(key)};
}
