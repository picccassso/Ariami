part of 'playback_manager.dart';

extension _PlaybackManagerVolumeImpl on PlaybackManager {
  String? get _volumeOutputId {
    final remote = _connectRemote;
    if (remote != null) {
      if (remote.deviceType != 'desktop' ||
          !_connectSupportsVolume ||
          _sendConnectCommand == null) {
        return null;
      }
      return 'connect:${remote.deviceId}:${remote.snapshot.castDeviceName ?? ''}';
    }
    if (!_castService.isConnected) return null;
    final session = GoogleCastSessionManager.instance.currentSession;
    return 'cast:${session?.device?.deviceID}:${session?.sessionID}';
  }

  void _setOutputVolumeImpl(double value, {required String outputId}) {
    if (outputId != volumeOutputId || !value.isFinite) return;
    final volume = value.clamp(0.0, 1.0).toDouble();
    if (_connectRemote == null) {
      _castService.setDeviceVolume(volume);
      _notifyStateChanged();
      return;
    }
    _pendingConnectVolume = volume;
    _pendingVolumeOutputId = outputId;
    _applyConnectOptimistic(volume: volume);
    // Keep the latest value without restarting the timer on every drag tick.
    _connectVolumeTimer ??= Timer(
      const Duration(milliseconds: 150),
      _flushConnectVolume,
    );
  }

  void _flushConnectVolume() {
    final volume = _pendingConnectVolume;
    final outputId = _pendingVolumeOutputId;
    _cancelConnectVolume();
    if (volume == null || outputId != volumeOutputId) return;
    _sendConnect(AriamiConnectCommand.setVolume, {'volume': volume});
  }

  void _cancelConnectVolume() {
    _connectVolumeTimer?.cancel();
    _connectVolumeTimer = null;
    _pendingConnectVolume = null;
    _pendingVolumeOutputId = null;
  }
}
