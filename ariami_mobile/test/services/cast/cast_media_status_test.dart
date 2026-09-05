import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ariami_mobile/services/cast/cast_playback_watchdog.dart';

// Shape observed in the Android SDK's status after a Home Mini loads an MP3.
Map<String, dynamic> receiverStatus(String state) => {
      'mediaSessionId': 1,
      'playerState': state,
      'playbackRate': 1,
      'volume': {'level': 1, 'muted': false},
      'repeatMode': 'REPEAT_OFF',
      'activeTrackIds': '[]',
      'media': {
        'contentId': 'http://192.0.2.1:8080/api/stream/test-song',
        'streamType': 'BUFFERED',
        'contentType': 'audio/mpeg',
        'duration': 160.08,
        'tracks': [
          {'trackId': 1, 'type': 'AUDIO'},
        ],
      },
    };

void main() {
  for (final state in ['PAUSED', 'PLAYING']) {
    testWidgets('$state with an in-band audio track clears the loading timeout',
        (tester) async {
      var failures = 0;
      final watchdog = CastPlaybackWatchdog(onFailure: () => failures++);
      addTearDown(watchdog.dispose);
      watchdog.update(
        isConnected: true,
        songId: 'test-song',
        playerState: CastMediaPlayerState.buffering,
        idleReason: null,
      );
      await tester.pump(const Duration(seconds: 1));

      final status =
          GoogleCastAndroidMediaStatus.fromMap(receiverStatus(state));
      expect(status.playerState.name.toUpperCase(), state);
      expect(status.mediaInformation!.duration, const Duration(seconds: 160));
      final track = status.mediaInformation!.tracks!.single;
      expect(track.trackId, 1);
      expect(track.type, TrackType.audio);
      expect(track.trackContentType, isEmpty);
      watchdog.update(
        isConnected: true,
        songId: 'test-song',
        playerState: status.playerState,
        idleReason: status.idleReason,
      );
      await tester.pump(const Duration(seconds: 16));
      expect(failures, 0);
    });
  }

  test('accepts an explicitly null track content type', () {
    final track = GoogleCastMediaTrack.fromMap({
      'trackId': 1,
      'type': 'AUDIO',
      'trackContentType': null,
    });
    expect(track.trackContentType, isEmpty);
  });

  test('preserves a supplied track content type', () {
    final track = GoogleCastMediaTrack.fromMap({
      'trackId': 1,
      'type': 'AUDIO',
      'trackContentType': 'audio/mpeg',
    });
    expect(track.trackContentType, 'audio/mpeg');
  });
}
