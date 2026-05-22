import 'package:ariami_mobile/models/repeat_mode.dart';
import 'package:ariami_mobile/widgets/player/player_artwork_indices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('playerArtworkWrapEnabled', () {
    test('enabled only for repeat-all with more than one song', () {
      expect(
        playerArtworkWrapEnabled(
          repeatMode: RepeatMode.all,
          queueLength: 3,
        ),
        isTrue,
      );
      expect(
        playerArtworkWrapEnabled(
          repeatMode: RepeatMode.all,
          queueLength: 1,
        ),
        isFalse,
      );
      expect(
        playerArtworkWrapEnabled(
          repeatMode: RepeatMode.none,
          queueLength: 3,
        ),
        isFalse,
      );
      expect(
        playerArtworkWrapEnabled(
          repeatMode: RepeatMode.one,
          queueLength: 3,
        ),
        isFalse,
      );
    });
  });

  group('playerArtworkPageCount', () {
    test('adds sentinel pages when wrap is enabled', () {
      expect(
        playerArtworkPageCount(wrapEnabled: true, queueLength: 4),
        6,
      );
      expect(
        playerArtworkPageCount(wrapEnabled: false, queueLength: 4),
        4,
      );
      expect(
        playerArtworkPageCount(wrapEnabled: true, queueLength: 0),
        0,
      );
    });
  });

  group('queue and page index mapping', () {
    const queueLength = 4;

    test('round-trips inner pages when wrap is enabled', () {
      for (var queueIndex = 0; queueIndex < queueLength; queueIndex++) {
        final pageIndex = playerArtworkQueueIndexToPageIndex(
          queueIndex: queueIndex,
          wrapEnabled: true,
          queueLength: queueLength,
        );
        expect(pageIndex, queueIndex + 1);

        expect(
          playerArtworkPageIndexToQueueIndex(
            pageIndex: pageIndex,
            wrapEnabled: true,
            queueLength: queueLength,
          ),
          queueIndex,
        );
      }
    });

    test('maps sentinel pages to wrapped queue indices', () {
      expect(
        playerArtworkPageIndexToQueueIndex(
          pageIndex: 0,
          wrapEnabled: true,
          queueLength: queueLength,
        ),
        queueLength - 1,
      );
      expect(
        playerArtworkPageIndexToQueueIndex(
          pageIndex: queueLength + 1,
          wrapEnabled: true,
          queueLength: queueLength,
        ),
        0,
      );
    });

    test('uses linear mapping when wrap is disabled', () {
      expect(
        playerArtworkQueueIndexToPageIndex(
          queueIndex: 2,
          wrapEnabled: false,
          queueLength: queueLength,
        ),
        2,
      );
      expect(
        playerArtworkPageIndexToQueueIndex(
          pageIndex: 2,
          wrapEnabled: false,
          queueLength: queueLength,
        ),
        2,
      );
    });
  });

  group('playerArtworkAnimateTargetPageIndex', () {
    const queueLength = 4;

    test('uses sentinel page for wrap-next from last track', () {
      expect(
        playerArtworkAnimateTargetPageIndex(
          fromQueueIndex: 3,
          toQueueIndex: 0,
          wrapEnabled: true,
          queueLength: queueLength,
        ),
        queueLength + 1,
      );
    });

    test('uses sentinel page for wrap-previous from first track', () {
      expect(
        playerArtworkAnimateTargetPageIndex(
          fromQueueIndex: 0,
          toQueueIndex: 3,
          wrapEnabled: true,
          queueLength: queueLength,
        ),
        0,
      );
    });

    test('uses inner pages for non-wrap transitions', () {
      expect(
        playerArtworkAnimateTargetPageIndex(
          fromQueueIndex: 1,
          toQueueIndex: 2,
          wrapEnabled: true,
          queueLength: queueLength,
        ),
        3,
      );
    });
  });

  group('playerArtworkIsSentinelPageIndex', () {
    test('identifies only wrap sentinel pages', () {
      expect(
        playerArtworkIsSentinelPageIndex(
          pageIndex: 0,
          wrapEnabled: true,
          queueLength: 4,
        ),
        isTrue,
      );
      expect(
        playerArtworkIsSentinelPageIndex(
          pageIndex: 5,
          wrapEnabled: true,
          queueLength: 4,
        ),
        isTrue,
      );
      expect(
        playerArtworkIsSentinelPageIndex(
          pageIndex: 2,
          wrapEnabled: true,
          queueLength: 4,
        ),
        isFalse,
      );
      expect(
        playerArtworkIsSentinelPageIndex(
          pageIndex: 0,
          wrapEnabled: false,
          queueLength: 4,
        ),
        isFalse,
      );
    });
  });
}
