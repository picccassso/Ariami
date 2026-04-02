import 'dart:async';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/media/media_request_scheduler.dart';
import 'package:ariami_mobile/widgets/common/cached_artwork.dart';
import 'package:ariami_mobile/widgets/library/playlist_card.dart';
import 'package:ariami_mobile/widgets/library/playlist_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_support/sqflite_mock.dart';

void main() {
  group('Phase 8 - P8-1 scheduler', () {
    final scheduler = MediaRequestScheduler();

    test('limits foreground artwork concurrency to 3', () async {
      var running = 0;
      var maxRunning = 0;
      final gate = Completer<void>();

      final futures = List.generate(
        8,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            running++;
            if (running > maxRunning) {
              maxRunning = running;
            }
            await gate.future;
            running--;
            return 1;
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(maxRunning, lessThanOrEqualTo(3));

      gate.complete();
      final results = await Future.wait(futures);
      expect(results.whereType<int>().length, 8);
    });

    test('limits background artwork concurrency to 1', () async {
      var running = 0;
      var maxRunning = 0;
      final gate = Completer<void>();

      final futures = List.generate(
        5,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.background,
          task: () async {
            running++;
            if (running > maxRunning) {
              maxRunning = running;
            }
            await gate.future;
            running--;
            return 1;
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(maxRunning, lessThanOrEqualTo(1));

      gate.complete();
      final results = await Future.wait(futures);
      expect(results.whereType<int>().length, 5);
    });

    test('drops stale low-priority queue entries when queue exceeds limit',
        () async {
      final foregroundGate = Completer<void>();
      final backgroundGate = Completer<void>();

      final occupyingFutures = <Future<int?>>[
        scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            await foregroundGate.future;
            return 1;
          },
        ),
        scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            await foregroundGate.future;
            return 1;
          },
        ),
        scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            await foregroundGate.future;
            return 1;
          },
        ),
        scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.background,
          task: () async {
            await backgroundGate.future;
            return 1;
          },
        ),
      ];

      // Queue beyond max low-priority queue length (200).
      final queuedFutures = List.generate(
        210,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.background,
          task: () async => 1,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      foregroundGate.complete();
      backgroundGate.complete();

      final queuedResults = await Future.wait(queuedFutures);
      await Future.wait(occupyingFutures);

      final droppedCount = queuedResults.where((value) => value == null).length;
      expect(droppedCount, greaterThanOrEqualTo(10));
    });

    test('cancels queued request before execution', () async {
      final gate = Completer<void>();
      final occupying = List.generate(
        3,
        (_) => scheduler.enqueueArtwork<int>(
          priority: MediaRequestPriority.visibleNow,
          task: () async {
            await gate.future;
            return 1;
          },
        ),
      );

      var started = false;
      final cancellationToken = MediaRequestCancellationToken();
      final cancelledFuture = scheduler.enqueueArtwork<int>(
        priority: MediaRequestPriority.visibleNow,
        cancellationToken: cancellationToken,
        task: () async {
          started = true;
          return 1;
        },
      );

      cancellationToken.cancel();
      gate.complete();

      final cancelledResult = await cancelledFuture;
      await Future.wait(occupying);

      expect(started, isFalse);
      expect(cancelledResult, isNull);
    });
  });

  group('Phase 8 - P8-2 playlist artwork id handling', () {
    setUpAll(installSqfliteTestMocks);
    tearDownAll(uninstallSqfliteTestMocks);

    PlaylistModel buildPlaylist({
      required String id,
      required List<String> songIds,
      required Map<String, String> songAlbumIds,
    }) {
      final now = DateTime(2026, 2, 7);
      return PlaylistModel(
        id: id,
        name: 'Playlist $id',
        songIds: songIds,
        songAlbumIds: songAlbumIds,
        createdAt: now,
        modifiedAt: now,
      );
    }

    testWidgets(
        'PlaylistCard uses parsed album id for album-first collage token',
        (tester) async {
      final playlist = buildPlaylist(
        id: 'playlist-card',
        songIds: const ['song-1'],
        songAlbumIds: const {'song-1': 'album-1'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 320,
              child: PlaylistCard(
                playlist: playlist,
                onTap: () {},
                albumIds: const ['a:album-1|s:song-1'],
              ),
            ),
          ),
        ),
      );

      final artworks =
          tester.widgetList<CachedArtwork>(find.byType(CachedArtwork)).toList();
      expect(artworks, isNotEmpty);
      expect(
        artworks.map((widget) => widget.albumId),
        contains('album-1'),
      );
      expect(
        artworks.map((widget) => widget.sizeHint),
        everyElement(ArtworkSizeHint.thumbnail),
      );
    });

    testWidgets(
        'PlaylistListItem uses song artwork key for song-only collage token',
        (tester) async {
      final playlist = buildPlaylist(
        id: 'playlist-list',
        songIds: const ['song-9'],
        songAlbumIds: const {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistListItem(
              playlist: playlist,
              onTap: () {},
              albumIds: const ['s:song-9'],
            ),
          ),
        ),
      );

      final artworks =
          tester.widgetList<CachedArtwork>(find.byType(CachedArtwork)).toList();
      expect(artworks, isNotEmpty);
      expect(
        artworks.map((widget) => widget.albumId),
        contains('song_song-9'),
      );
    });
  });
}
