part of '../audio_controller.dart';

T _enumByIndex<T>(List<T> values, int? index, T fallback) {
  if (index == null || index < 0 || index >= values.length) return fallback;
  return values[index];
}

extension _AudioControllerPersistence on AudioController {
  void _scheduleSave() {
    if (_restoring) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastSaveMs;
    if (elapsed >= AudioController._saveIntervalMs) {
      _lastSaveMs = now;
      _saveTimer?.cancel();
      unawaited(_persist());
    } else {
      _saveTimer?.cancel();
      _saveTimer = Timer(
          Duration(milliseconds: AudioController._saveIntervalMs - elapsed),
          () {
        _lastSaveMs = DateTime.now().millisecondsSinceEpoch;
        unawaited(_persist());
      });
    }
  }

  Future<void> _persist() async {
    if (_restoring) return;
    // Nothing to save yet. Crucially we do *not* remove the saved key here:
    // the player's streams fire (with an empty queue) at startup before
    // restore() runs, and clearing on empty would wipe the previous session.
    // Removal happens only via clear() (disconnect/logout) or when restore()
    // hits corrupt state.
    if (_queue.isEmpty || _orderPos < 0) return;
    _prefs ??= await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'queue': _queue.map((t) => t.toJson()).toList(),
      'playOrder': _playOrder,
      'orderPos': _orderPos,
      'shuffle': _shuffle,
      'repeat': _repeat.index,
      // Keeps the restored session pointing at the album/playlist it came
      // from, so the "now playing" indicator returns after a restart.
      'sourceId': _sourceId,
      // Kept in the queue snapshot for backwards compatibility. The dedicated
      // preference key below survives disconnects and mode changes.
      'quality': quality.index,
      'volume': _volume,
      'positionMs': position.inMilliseconds,
    };
    final encoded = jsonEncode(data);
    if (_prefs!.getString(AudioController._stateKey) == encoded) return;
    await _prefs!.setString(AudioController._stateKey, encoded);
  }

  Future<void> _persistQualityPreference() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(AudioController._qualityPreferenceKey, quality.index);
  }
}
