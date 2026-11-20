import '../player/services/player_host.dart';

class WebAudioEqualizerBackend implements EqualizerBackend {
  @override
  bool get isSupported => false;

  @override
  Future<void> apply({
    required bool enabled,
    required List<int> frequencies,
    required List<double> gains,
  }) async {}
}

class WebAudioLevelMeterBackend implements LevelMeterBackend {
  @override
  bool get isSupported => false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<LevelMeterReading?> read() async => null;
}
