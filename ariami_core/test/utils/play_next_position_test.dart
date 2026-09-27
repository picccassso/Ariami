import 'package:ariami_core/utils/play_next_position.dart';
import 'package:test/test.dart';

void main() {
  // Queue of ids by position; 'p1'/'p2' stand for earlier Play next picks.
  int place(List<String> queue, int current,
          {bool stack = true, String? tail, int? hint}) =>
      playNextPosition(
        current: current,
        length: queue.length,
        stack: stack,
        tailHint: hint,
        isTail: tail == null ? null : (i) => queue[i] == tail,
      );

  test('defaults to straight after the current item', () {
    expect(place(['a', 'p1', 'b'], 0, stack: false, tail: 'p1'), 1);
  });

  test('stacks after the last earlier pick still waiting', () {
    expect(place(['a', 'p1', 'p2', 'b'], 0, tail: 'p2'), 3);
  });

  test('starts afresh once playback reaches the last pick', () {
    expect(place(['a', 'p1', 'b'], 1, tail: 'p1'), 2);
    expect(place(['p1', 'a', 'p1'], 1, tail: 'p1', hint: 0), 2);
  });

  test('finds the pick again after removals move it earlier', () {
    expect(place(['a', 'p2', 'b'], 0, tail: 'p2', hint: 2), 2);
  });

  test('falls back when the pick is gone, and clamps to the queue', () {
    expect(place(['a', 'b'], 0, tail: 'p1'), 1);
    expect(place([], -1), 0);
    expect(place(['a'], 0, tail: 'p1', hint: 9), 1);
  });
}
