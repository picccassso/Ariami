import 'package:ariami_core/models/connect_models.dart';
import 'package:test/test.dart';

void main() {
  group('slice 7 payload bounds', () {
    test('[raw_message_limit] input above measured 8 MiB is rejected', () {
      expect(isConnectRawMessageWithinLimit('{}'), isTrue);
      expect(
        isConnectRawMessageWithinLimit(
          'x' * (kMaxConnectRawMessageBytes + 1),
        ),
        isFalse,
      );
    });

    test('[bounded_command_shapes] accepts real long-tail track metadata', () {
      // Measured against 274,360 real plays: the longest title is a
      // 203-character medley. Bounds must clear the long tail of real tags,
      // because one rejected track fails the whole queue publication.
      final validated = validateConnectCommandArguments(
        AriamiConnectCommand.insertQueueTrack,
        <String, dynamic>{
          'index': 0,
          'track': <String, dynamic>{
            'id': 'a1b2c3d4e5f6',
            'title': 'Medley: ${'Lawdy, Miss Clawdy / ' * 10}All Shook Up',
            'artist': 'A' * 300,
            'album': 'B' * 300,
            'filePath': '/Volumes/Music/${'nested folder/' * 30}track.mp3',
          },
        },
      );
      final track = Map<String, dynamic>.from(validated['track'] as Map);
      expect((track['title'] as String).length, greaterThan(200));
      expect((track['filePath'] as String).length, greaterThan(400));
    });

    test('[bounded_command_shapes] rejects nesting and oversized strings', () {
      expect(
        () => validateConnectCommandArguments(
          AriamiConnectCommand.seek,
          <String, dynamic>{
            'positionMs': 1,
            'nested': <String, dynamic>{'unexpected': true},
          },
        ),
        throwsFormatException,
      );
      expect(
        () => validateConnectCommandArguments(
          AriamiConnectCommand.insertQueueTrack,
          <String, dynamic>{
            'index': 0,
            'track': <String, dynamic>{
              'id': 'x' * 65,
              'title': 'Song',
            },
          },
        ),
        throwsFormatException,
      );
      expect(
        () => validateConnectCommandArguments(
          AriamiConnectCommand.insertQueueTrack,
          <String, dynamic>{
            'index': 0,
            'track': <String, dynamic>{'id': 7},
          },
        ),
        throwsFormatException,
      );
      expect(
        () => validateConnectCommandArguments(
          AriamiConnectCommand.playContext,
          <String, dynamic>{
            'snapshot': <String, dynamic>{
              'queue': <Map<String, dynamic>>[],
              'currentIndex': 'zero',
            },
          },
        ),
        throwsFormatException,
      );
    });

    test('[play_context_backing_order] preserves order and rejects overflow',
        () {
      final validated = validateConnectCommandArguments(
        AriamiConnectCommand.playContext,
        <String, dynamic>{
          'snapshot': <String, dynamic>{
            'queue': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'duplicate', 'title': 'First'},
              <String, dynamic>{'id': 'duplicate', 'title': 'Second'},
            ],
            'backingOrder': <int>[1, 0],
            'currentIndex': 0,
            'positionMs': 0,
            'durationMs': 1000,
            'isPlaying': true,
            'shuffle': true,
            'repeatMode': 'off',
            'volume': 1,
          },
        },
      );
      final snapshot = Map<String, dynamic>.from(validated['snapshot'] as Map);
      expect(snapshot['backingOrder'], <int>[1, 0]);

      expect(
        () => validateConnectCommandArguments(
          AriamiConnectCommand.playContext,
          <String, dynamic>{
            'snapshot': <String, dynamic>{
              'queue': List<Map<String, dynamic>>.generate(
                AriamiPlaybackSnapshot.maxQueueLength + 1,
                (index) => <String, dynamic>{'id': 'track-$index'},
              ),
            },
          },
        ),
        throwsFormatException,
      );
    });
  });

  test('clear queue is a supported Connect command', () {
    expect(
      AriamiConnectCommand.supported,
      contains(AriamiConnectCommand.clearQueue),
    );
  });

  test('device capabilities default for legacy peers and narrow safely', () {
    final legacy = AriamiConnectDevice.fromJson(const <String, dynamic>{
      'id': 'legacy',
    });
    final narrowed = AriamiConnectDevice.fromJson(const <String, dynamic>{
      'id': 'tv',
      'supportedCommands': <String>[
        AriamiConnectCommand.pause,
        'invented_command',
      ],
    });

    expect(legacy.supportedCommands, AriamiConnectCommand.supported);
    expect(narrowed.supportedCommands, <String>{AriamiConnectCommand.pause});
    expect(
      narrowed.toJson()['supportedCommands'],
      <String>[AriamiConnectCommand.pause],
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

    test('split progress retains validated queue identity', () {
      final queue = List<Map<String, dynamic>>.unmodifiable(
        const <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a'},
          <String, dynamic>{'id': 'b'},
        ],
      );
      final backingOrder = List<int>.unmodifiable(const <int>[1, 0]);

      final first = AriamiPlaybackSnapshot.fromSplitState(
        const <String, dynamic>{
          'currentIndex': 0,
          'positionMs': 1000,
          'durationMs': 60000,
          'isPlaying': true,
        },
        queue: queue,
        backingOrder: backingOrder,
        sourceId: 'playlist:test',
      );
      final second = AriamiPlaybackSnapshot.fromSplitState(
        const <String, dynamic>{
          'currentIndex': 0,
          'positionMs': 2000,
          'durationMs': 60000,
          'isPlaying': true,
        },
        queue: queue,
        backingOrder: backingOrder,
        sourceId: 'playlist:test',
      );

      expect(identical(first.queue, second.queue), isTrue);
      expect(identical(first.backingOrder, second.backingOrder), isTrue);
      expect(second.positionMs, 2000);
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
