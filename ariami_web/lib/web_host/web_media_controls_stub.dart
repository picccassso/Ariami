import 'dart:typed_data';

import '../player/services/player_host.dart';

class WebMediaControlsBackend implements MediaControlsBackend {
  @override
  Future<void> initialize(MediaCommandHandler onCommand) async {}

  @override
  Future<void> setMetadata(MediaNowPlaying info) async {}

  @override
  Future<void> setPlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {}

  @override
  Future<void> setArtwork(String trackId, Uint8List bytes) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}
