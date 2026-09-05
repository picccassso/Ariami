import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/services/cast/cast_playback_watchdog.dart';

void main() {
  test('continuous loading triggers one failure without extending timeout',
      () async {
    var failures = 0;
    final watchdog = CastPlaybackWatchdog(
      stallTimeout: const Duration(milliseconds: 100),
      onFailure: () => failures++,
    );

    watchdog.update(
      isConnected: true,
      songId: 'song-1',
      playerState: CastMediaPlayerState.loading,
      idleReason: null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    watchdog.update(
      isConnected: true,
      songId: 'song-1',
      playerState: CastMediaPlayerState.buffering,
      idleReason: null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(failures, 1);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(failures, 1);
    watchdog.dispose();
  });

  test('playing cancels a pending loading failure', () async {
    var failures = 0;
    final watchdog = CastPlaybackWatchdog(
      stallTimeout: const Duration(milliseconds: 100),
      onFailure: () => failures++,
    );

    watchdog.update(
      isConnected: true,
      songId: 'song-1',
      playerState: CastMediaPlayerState.loading,
      idleReason: null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    watchdog.update(
      isConnected: true,
      songId: 'song-1',
      playerState: CastMediaPlayerState.playing,
      idleReason: null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(failures, 0);
    watchdog.dispose();
  });

  test('receiver error triggers immediately and only once per song', () {
    var failures = 0;
    final watchdog = CastPlaybackWatchdog(onFailure: () => failures++);

    for (var i = 0; i < 2; i++) {
      watchdog.update(
        isConnected: true,
        songId: 'song-1',
        playerState: CastMediaPlayerState.idle,
        idleReason: GoogleCastMediaIdleReason.error,
      );
    }
    expect(failures, 1);

    watchdog.update(
      isConnected: true,
      songId: 'song-2',
      playerState: CastMediaPlayerState.idle,
      idleReason: GoogleCastMediaIdleReason.error,
    );
    expect(failures, 2);
  });

  test('disconnect cancels a pending loading failure', () async {
    var failures = 0;
    final watchdog = CastPlaybackWatchdog(
      stallTimeout: const Duration(milliseconds: 50),
      onFailure: () => failures++,
    );

    watchdog.update(
      isConnected: true,
      songId: 'song-1',
      playerState: CastMediaPlayerState.loading,
      idleReason: null,
    );
    watchdog.update(
      isConnected: false,
      songId: 'song-1',
      playerState: CastMediaPlayerState.loading,
      idleReason: null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(failures, 0);
    watchdog.dispose();
  });
}
