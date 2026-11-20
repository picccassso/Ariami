import 'dart:js_interop';

import '../player/services/player_host.dart';

@JS('ariamiWebAudio')
external JSAny? get _ariamiWebAudioAny;

extension type _AriamiWebAudioJs._(JSObject _) implements JSObject {
  external void setEqualizer(
    bool enabled,
    JSArray<JSNumber> frequencies,
    JSArray<JSNumber> gains,
  );
  external void setMeteringEnabled(bool enabled);
  external _SampleBandsResultJs? sampleBands();
}

extension type _SampleBandsResultJs._(JSObject _) implements JSObject {
  external JSArray<JSNumber> get bands;
  external double get dt;
}

_AriamiWebAudioJs? get _webAudio {
  final raw = _ariamiWebAudioAny;
  if (raw == null || raw.isUndefinedOrNull) return null;
  return raw as _AriamiWebAudioJs;
}

class WebAudioEqualizerBackend implements EqualizerBackend {
  @override
  bool get isSupported => _webAudio != null;

  @override
  Future<void> apply({
    required bool enabled,
    required List<int> frequencies,
    required List<double> gains,
  }) async {
    final bridge = _webAudio;
    if (bridge == null) return;
    bridge.setEqualizer(
      enabled,
      <JSNumber>[for (final f in frequencies) f.toJS].toJS,
      <JSNumber>[for (final g in gains) g.toJS].toJS,
    );
  }
}

class WebAudioLevelMeterBackend implements LevelMeterBackend {
  @override
  bool get isSupported => _webAudio != null;

  @override
  Future<void> setEnabled(bool enabled) async {
    _webAudio?.setMeteringEnabled(enabled);
  }

  @override
  Future<LevelMeterReading?> read() async {
    final sample = _webAudio?.sampleBands();
    if (sample == null) return null;
    final dt = sample.dt;
    if (!dt.isFinite || dt <= 0) return null;
    final bands = <double>[
      for (final value in sample.bands.toDart) value.toDartDouble,
    ];
    if (bands.length < 11) return null;
    return LevelMeterReading(
      readings: <List<double>>[bands],
      blockSeconds: dt,
    );
  }
}
