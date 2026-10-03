/// Fences asynchronous local playback when another device takes ownership.
/// Completion must follow audible readiness and is consumed once, even when
/// pausing a completed player emits another completed state.
class PlaybackOperationGuard {
  int _generation = 0;
  bool _suspended = false;
  bool _completionArmed = false;
  int? _completionInFlight;

  int get generation => _generation;
  bool get isSuspended => _suspended;
  bool isCurrent(int generation) => generation == _generation;

  void invalidate({bool suspend = false}) {
    _generation++;
    _suspended = suspend;
    _completionArmed = false;
    _completionInFlight = null;
  }

  void disarmCompletion() => _completionArmed = false;

  int? observePlayerState({
    required bool playing,
    required bool ready,
    required bool completed,
  }) {
    if (_suspended || !playing) {
      _completionArmed = false;
      return null;
    }
    if (ready) {
      _completionArmed = true;
      return null;
    }
    if (!completed || !_completionArmed || _completionInFlight != null) {
      return null;
    }
    _completionArmed = false;
    return _completionInFlight = _generation;
  }

  void finishCompletion(int generation) {
    if (_completionInFlight == generation) _completionInFlight = null;
  }
}
