import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:test/test.dart';

AriamiPlaybackSnapshot _snapshot({
  bool isPlaying = true,
  int positionMs = 10000,
  int durationMs = 60000,
  int currentIndex = 0,
}) =>
    AriamiPlaybackSnapshot(
      queue: [
        {'id': 'a', 'title': 'One'},
        {'id': 'b', 'title': 'Two'},
      ],
      currentIndex: currentIndex,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      shuffle: false,
      repeatMode: 'off',
      volume: 1,
    );

AriamiRemotePlayback _remote(
  AriamiPlaybackSnapshot snapshot, {
  DateTime? receivedAt,
}) =>
    AriamiRemotePlayback(
      snapshot: snapshot,
      deviceId: 'tv-1',
      deviceName: 'Ariami TV',
      deviceType: 'tv',
      receivedAt: receivedAt,
    );

void main() {
  test('position extrapolates from local receipt time while playing', () {
    final remote = _remote(
      _snapshot(),
      receivedAt: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    expect(remote.positionMs, greaterThanOrEqualTo(15000));
    expect(remote.positionMs, lessThan(16000));
  });

  test('position does not advance while the remote device is paused', () {
    final remote = _remote(
      _snapshot(isPlaying: false),
      receivedAt: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    expect(remote.positionMs, 10000);
  });

  test('position clamps to the track duration', () {
    final remote = _remote(
      _snapshot(positionMs: 59000),
      receivedAt: DateTime.now().subtract(const Duration(seconds: 30)),
    );
    expect(remote.positionMs, 60000);
  });

  test('currentTrackJson returns the mirrored track and null out of range', () {
    expect(_remote(_snapshot()).currentTrackJson?['id'], 'a');
    final empty = AriamiPlaybackSnapshot.fromJson(const {'queue': []});
    expect(_remote(empty).currentTrackJson, isNull);
  });

  test('copyWithSnapshot re-anchors the receipt time', () {
    final stale = _remote(
      _snapshot(),
      receivedAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final adjusted =
        stale.copyWithSnapshot(stale.snapshot.copyWith(positionMs: 20000));
    expect(adjusted.positionMs, lessThan(21000));
    expect(adjusted.deviceName, 'Ariami TV');
  });

  test('play_queue_index is a supported command', () {
    expect(
      AriamiConnectCommand.supported,
      contains(AriamiConnectCommand.playQueueIndex),
    );
  });
}
