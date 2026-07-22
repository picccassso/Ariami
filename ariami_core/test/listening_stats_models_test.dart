import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:test/test.dart';

void main() {
  group('ListeningEvent wire compatibility', () {
    test('round-trips the optional source-context fields', () {
      const event = ListeningEvent(
        eventId: 'e1',
        songId: 'song-1',
        playId: 'play-1',
        listenedMs: 15000,
        plays: 0,
        occurredAtMs: 1700000000000,
        tzOffsetMinutes: 60,
        songTitle: 'Title',
        songArtist: 'Artist',
        albumId: 'album-1',
        album: 'Album',
        albumArtist: 'Album Artist',
        songDurationMs: 200000,
        sourceKind: 'playlist',
        playlistId: 'pl-1',
        clientKind: 'mobile',
      );

      final parsed = ListeningEvent.tryFromJson(event.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.sourceKind, 'playlist');
      expect(parsed.playlistId, 'pl-1');
      expect(parsed.clientKind, 'mobile');
      expect(parsed.listenedMs, 15000);
      expect(parsed.songDurationMs, 200000);
    });

    test('old-client events without source context parse with null fields', () {
      final parsed = ListeningEvent.tryFromJson(<String, dynamic>{
        'eventId': 'e-old',
        'songId': 'song-1',
        'listenedMs': 5000,
        'plays': 0,
        'occurredAtMs': 1700000000000,
        'tzOffsetMinutes': 0,
      });
      expect(parsed, isNotNull);
      expect(parsed!.sourceKind, isNull);
      expect(parsed.playlistId, isNull);
      expect(parsed.clientKind, isNull);
    });

    test('unset context fields are omitted from the wire payload', () {
      const event = ListeningEvent(
        eventId: 'e2',
        songId: 'song-2',
        listenedMs: 1000,
        plays: 0,
        occurredAtMs: 1700000000000,
        tzOffsetMinutes: 0,
      );
      final json = event.toJson();
      expect(json.containsKey('sourceKind'), isFalse);
      expect(json.containsKey('playlistId'), isFalse);
      expect(json.containsKey('clientKind'), isFalse);
    });

    test('album enrichment preserves event identity and playback context', () {
      const event = ListeningEvent(
        eventId: 'e-enrich',
        songId: 'song-1',
        playId: 'play-1',
        listenedMs: 15000,
        plays: 0,
        occurredAtMs: 1700000000000,
        tzOffsetMinutes: 60,
        songTitle: 'Title',
        songArtist: 'Track Artist',
        sourceKind: 'playlist',
        playlistId: 'playlist-1',
        clientKind: 'desktop',
      );

      final enriched = event.withAlbumMetadata(
        albumId: 'album-1',
        album: 'Album',
        albumArtist: 'Album Artist',
      );

      expect(enriched.eventId, event.eventId);
      expect(enriched.playId, event.playId);
      expect(enriched.listenedMs, event.listenedMs);
      expect(enriched.sourceKind, event.sourceKind);
      expect(enriched.playlistId, event.playlistId);
      expect(enriched.clientKind, event.clientKind);
      expect(enriched.albumId, 'album-1');
      expect(enriched.album, 'Album');
      expect(enriched.albumArtist, 'Album Artist');
    });

    test('unknown fields from newer producers are ignored', () {
      final parsed = ListeningEvent.tryFromJson(<String, dynamic>{
        'eventId': 'e-future',
        'songId': 'song-1',
        'listenedMs': 5000,
        'plays': 0,
        'occurredAtMs': 1700000000000,
        'tzOffsetMinutes': 0,
        'someFutureField': {'nested': true},
        'sourceKind': 'album',
      });
      expect(parsed, isNotNull);
      expect(parsed!.sourceKind, 'album');
    });

    test('non-string context values are treated as absent, not errors', () {
      final parsed = ListeningEvent.tryFromJson(<String, dynamic>{
        'eventId': 'e-bad',
        'songId': 'song-1',
        'listenedMs': 5000,
        'plays': 0,
        'occurredAtMs': 1700000000000,
        'tzOffsetMinutes': 0,
        'sourceKind': 42,
        'playlistId': ['pl'],
        'clientKind': null,
      });
      expect(parsed, isNotNull);
      expect(parsed!.sourceKind, isNull);
      expect(parsed.playlistId, isNull);
      expect(parsed.clientKind, isNull);
    });
  });

  group('ListeningStatsSummary.hasSpotifyImport', () {
    test('toJson always emits the field', () {
      const summary = ListeningStatsSummary(
        songs: <ListeningSongRollup>[],
        totalListenedMs: 0,
        totalPlays: 0,
        generatedAtMs: 123,
      );
      expect(summary.toJson()['hasSpotifyImport'], isFalse);

      const imported = ListeningStatsSummary(
        songs: <ListeningSongRollup>[],
        totalListenedMs: 0,
        totalPlays: 0,
        generatedAtMs: 123,
        hasSpotifyImport: true,
      );
      expect(imported.toJson()['hasSpotifyImport'], isTrue);
    });

    test('fromJson treats only the literal true as true', () {
      expect(
        ListeningStatsSummary.fromJson(const <String, dynamic>{
          'hasSpotifyImport': true,
        }).hasSpotifyImport,
        isTrue,
      );
    });

    test('fromJson maps missing, null and malformed values to false', () {
      final cases = <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{'hasSpotifyImport': null},
        <String, dynamic>{'hasSpotifyImport': false},
        <String, dynamic>{'hasSpotifyImport': 'true'},
        <String, dynamic>{'hasSpotifyImport': 1},
        <String, dynamic>{'hasSpotifyImport': 0},
        <String, dynamic>{'hasSpotifyImport': <dynamic>[]},
        <String, dynamic>{
          'hasSpotifyImport': <String, dynamic>{'value': true}
        },
      ];
      for (final json in cases) {
        expect(
          ListeningStatsSummary.fromJson(json).hasSpotifyImport,
          isFalse,
          reason: 'json: $json',
        );
      }
    });

    test('empty summary reports false and round-trips', () {
      expect(ListeningStatsSummary.empty.hasSpotifyImport, isFalse);
      final restored =
          ListeningStatsSummary.fromJson(ListeningStatsSummary.empty.toJson());
      expect(restored.hasSpotifyImport, isFalse);
    });
  });
}
