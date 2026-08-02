import 'package:ariami_core/models/connect_models.dart';
import 'package:test/test.dart';

void main() {
  test('clear queue is a supported Connect command', () {
    expect(
      AriamiConnectCommand.supported,
      contains(AriamiConnectCommand.clearQueue),
    );
  });

  group('repeatModeAfterExplicitTrackChange', () {
    test('widens repeat-one while preserving other repeat modes', () {
      expect(repeatModeAfterExplicitTrackChange('one'), 'all');
      expect(repeatModeAfterExplicitTrackChange('all'), 'all');
      expect(repeatModeAfterExplicitTrackChange('off'), 'off');
    });
  });

  group('AriamiPlaybackSnapshot', () {
    test('round trips a cross-client queue', () {
      final snapshot = AriamiPlaybackSnapshot(
        queue: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'song-1',
            'title': 'First',
            'artist': 'Artist',
            'duration': 240,
          },
        ],
        currentIndex: 0,
        positionMs: 12000,
        durationMs: 240000,
        isPlaying: true,
        shuffle: true,
        repeatMode: 'all',
        volume: 0.75,
        sourceId: 'album:one',
      );

      final restored = AriamiPlaybackSnapshot.fromJson(snapshot.toJson());
      expect(restored.currentTrackId, 'song-1');
      expect(restored.positionMs, 12000);
      expect(restored.shuffle, isTrue);
      expect(restored.repeatMode, 'all');
      expect(restored.volume, 0.75);
    });

    test(
        '[positional_duplicate_backing_order] positional backing order '
        'preserves duplicate occurrences', () {
      final snapshot = AriamiPlaybackSnapshot(
        queue: const <Map<String, dynamic>>[
          {'id': 'duplicate', 'title': 'Second occurrence'},
          {'id': 'unique', 'title': 'Unique'},
          {'id': 'duplicate', 'title': 'First occurrence'},
        ],
        backingOrder: const <int>[2, 0, 1],
        currentIndex: 0,
        positionMs: 0,
        durationMs: 60000,
        isPlaying: true,
        shuffle: true,
        repeatMode: 'off',
        volume: 1,
      );

      final restored = AriamiPlaybackSnapshot.fromJson(
        snapshot.toJson(includeBackingOrder: true),
      );
      expect(restored.backingOrder, <int>[2, 0, 1]);
      expect(
        restored.backingOrder.map((index) => restored.queue[index]['title']),
        <String>['First occurrence', 'Second occurrence', 'Unique'],
      );
      expect(snapshot.toJson().containsKey('backingOrder'), isFalse,
          reason: 'v2 reconstruction must retain its established shape');
    });

    test('rejects malformed backing-order permutations', () {
      for (final order in <List<int>>[
        <int>[0, 0],
        <int>[0],
        <int>[0, 2],
      ]) {
        expect(
          () => AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
            'queue': const <Map<String, dynamic>>[
              {'id': 'a'},
              {'id': 'b'},
            ],
            'backingOrder': order,
          }),
          throwsFormatException,
        );
      }
    });

    test(
        '[canonical_queue_fingerprint] canonical queue fingerprints ignore '
        'map key insertion order', () {
      final first = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        'queue': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'title': 'A'},
        ],
      });
      final second = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        'queue': <Map<String, dynamic>>[
          <String, dynamic>{'title': 'A', 'id': 'a'},
        ],
      });
      expect(first.queueFingerprint, second.queueFingerprint);
    });

    test('compensates a playing handoff for transport time', () {
      final updatedAt = DateTime.utc(2026, 1, 1, 12);
      final snapshot = AriamiPlaybackSnapshot(
        queue: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'song-1'},
        ],
        currentIndex: 0,
        positionMs: 10000,
        durationMs: 60000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
        updatedAt: updatedAt,
      );

      final compensated =
          snapshot.compensated(updatedAt.add(const Duration(seconds: 3)));
      expect(compensated.positionMs, 13000);
      expect(compensated.updatedAt, updatedAt.add(const Duration(seconds: 3)));
    });

    test('repeated handoff compensation counts each interval only once', () {
      final updatedAt = DateTime.utc(2026, 1, 1, 12);
      final snapshot = AriamiPlaybackSnapshot(
        queue: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'song-1'},
        ],
        currentIndex: 0,
        positionMs: 10000,
        durationMs: 60000,
        isPlaying: true,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
        updatedAt: updatedAt,
      );

      // A transfer is compensated at multiple hops. Four one-second hops must
      // advance four seconds in total, rather than re-adding time since the
      // original snapshot at every hop (1 + 2 + 3 + 4 seconds).
      var handedOff = snapshot;
      for (var seconds = 1; seconds <= 4; seconds++) {
        handedOff = handedOff.compensated(
          updatedAt.add(Duration(seconds: seconds)),
        );
      }

      expect(handedOff.positionMs, 14000);
      expect(handedOff.updatedAt, updatedAt.add(const Duration(seconds: 4)));
    });

    test('does not compensate a paused handoff', () {
      final updatedAt = DateTime.utc(2026, 1, 1, 12);
      final snapshot = AriamiPlaybackSnapshot(
        queue: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'song-1'},
        ],
        currentIndex: 0,
        positionMs: 10000,
        durationMs: 60000,
        isPlaying: false,
        shuffle: false,
        repeatMode: 'off',
        volume: 1,
        updatedAt: updatedAt,
      );

      expect(
        snapshot
            .compensated(updatedAt.add(const Duration(seconds: 3)))
            .positionMs,
        10000,
      );
    });

    test('copyWith can update repeat mode without changing the queue', () {
      final snapshot = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        'queue': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'song-1'},
        ],
        'currentIndex': 0,
        'repeatMode': 'one',
      });

      final updated = snapshot.copyWith(repeatMode: 'all');
      expect(updated.repeatMode, 'all');
      expect(updated.currentTrackId, 'song-1');
    });

    test('bounds untrusted wire values', () {
      final snapshot = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        'queue': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'song-1'},
        ],
        'currentIndex': 99,
        'positionMs': -10,
        'durationMs': 999999999,
        'volume': 4,
        'repeatMode': 'surprise',
      });

      expect(snapshot.currentIndex, 0);
      expect(snapshot.positionMs, 0);
      expect(snapshot.durationMs, 86400000);
      expect(snapshot.volume, 1);
      expect(snapshot.repeatMode, 'off');
    });

    test('rejects an abusive queue size', () {
      expect(
        () => AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
          'queue': List<Map<String, dynamic>>.generate(
            AriamiPlaybackSnapshot.maxQueueLength + 1,
            (index) => <String, dynamic>{'id': '$index'},
          ),
        }),
        throwsFormatException,
      );
    });
  });
}
