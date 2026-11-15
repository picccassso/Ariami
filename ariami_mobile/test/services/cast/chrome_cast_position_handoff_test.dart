import 'package:ariami_mobile/services/cast/chrome_cast_service.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  installSqfliteTestMocks();
  final cast = ChromeCastService();

  tearDownAll(uninstallSqfliteTestMocks);
  setUp(cast.resetPositionStateForTest);
  tearDown(cast.resetPositionStateForTest);

  test('handoff keeps target position across connecting and buffering zero ticks',
      () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const handoff = Duration(seconds: 105);

    cast.seedHandoffPositionForTest(handoff, at: t0, connecting: true);
    expect(cast.remotePosition, handoff);
    expect(
      cast.applyRemotePositionUpdate(
        Duration.zero,
        playerState: CastMediaPlayerState.loading,
        now: t0.add(const Duration(milliseconds: 500)),
      ),
      isFalse,
    );
    expect(cast.remotePosition, handoff);

    cast.seedHandoffPositionForTest(handoff, at: t0, connecting: false);
    expect(
      cast.applyRemotePositionUpdate(
        Duration.zero,
        playerState: CastMediaPlayerState.buffering,
        now: t0.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(cast.remotePosition, handoff);

    expect(
      cast.applyRemotePositionUpdate(
        const Duration(seconds: 105),
        playerState: CastMediaPlayerState.playing,
        now: t0.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
    expect(cast.remotePosition, const Duration(seconds: 105));
  });

  test('ignores stale position briefly when playing then reconciles after grace',
      () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    cast.seedHandoffPositionForTest(const Duration(seconds: 90), at: t0);

    expect(
      cast.applyRemotePositionUpdate(
        Duration.zero,
        playerState: CastMediaPlayerState.playing,
        now: t0.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(cast.remotePosition, const Duration(seconds: 90));

    expect(
      cast.applyRemotePositionUpdate(
        const Duration(seconds: 5),
        playerState: CastMediaPlayerState.playing,
        now: t0.add(const Duration(seconds: 5)),
      ),
      isTrue,
    );
    expect(cast.remotePosition, const Duration(seconds: 5));
  });
}
