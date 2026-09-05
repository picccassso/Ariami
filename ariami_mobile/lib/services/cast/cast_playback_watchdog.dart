import 'dart:async';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

/// Detects receiver failures that would otherwise leave Cast playback loading
/// forever. Repeated status broadcasts do not extend the timeout.
class CastPlaybackWatchdog {
  CastPlaybackWatchdog({
    required this.onFailure,
    this.stallTimeout = const Duration(seconds: 15),
  });

  final void Function() onFailure;
  final Duration stallTimeout;

  Timer? _stallTimer;
  String? _songId;
  bool _failureSignalled = false;

  void update({
    required bool isConnected,
    required String? songId,
    required CastMediaPlayerState? playerState,
    required GoogleCastMediaIdleReason? idleReason,
  }) {
    if (!isConnected || songId == null) {
      reset();
      return;
    }

    if (_songId != songId) {
      _stallTimer?.cancel();
      _stallTimer = null;
      _songId = songId;
      _failureSignalled = false;
    }

    if (playerState == CastMediaPlayerState.playing ||
        playerState == CastMediaPlayerState.paused) {
      _cancelStall();
      _failureSignalled = false;
      return;
    }

    if (playerState == CastMediaPlayerState.idle) {
      _cancelStall();
      if (idleReason == GoogleCastMediaIdleReason.error) {
        _signalFailure();
      }
      return;
    }

    final isStalled = playerState == CastMediaPlayerState.loading ||
        playerState == CastMediaPlayerState.buffering;
    if (!isStalled) {
      _cancelStall();
      return;
    }

    _stallTimer ??= Timer(stallTimeout, _signalFailure);
  }

  void reset() {
    _cancelStall();
    _songId = null;
    _failureSignalled = false;
  }

  void dispose() => reset();

  void _cancelStall() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  void _signalFailure() {
    _cancelStall();
    if (_failureSignalled) return;
    _failureSignalled = true;
    onFailure();
  }
}
