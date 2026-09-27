/// Where "Play next" inserts into a queue of [length] items playing [current].
///
/// By default it is straight after the current item, so the latest pick plays
/// first. With [stack] on it is after the earlier Play next picks still
/// waiting, so picks play in the order they were chosen: [isTail] recognises
/// the last of those picks, searched from [tailHint] (or the end) back towards
/// [current] — edits before the run only ever move it earlier. Once playback
/// reaches that pick, the next one goes straight after the current item again.
int playNextPosition({
  required int current,
  required int length,
  bool stack = false,
  bool Function(int index)? isTail,
  int? tailHint,
}) {
  if (stack && isTail != null) {
    final from = tailHint == null || tailHint >= length ? length - 1 : tailHint;
    for (var i = from; i > current; i--) {
      if (isTail(i)) return i + 1;
    }
  }
  return (current + 1).clamp(0, length);
}
