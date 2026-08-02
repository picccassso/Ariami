import 'package:ariami_mobile/services/audio/shuffle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queue synchronization permanently removes an exact duplicate', () {
    final firstA = _Item('a', 'first');
    final secondA = _Item('a', 'second');
    final b = _Item('b', 'b');
    final c = _Item('c', 'c');
    final service = ShuffleService<_Item>();
    service.enableShuffle([firstA, b, secondA, c], b);

    service.synchronizeQueue([b, secondA, c]);

    expect(service.originalQueue, [b, secondA, c]);
    expect(
        service.originalQueue.any((item) => identical(item, firstA)), isFalse);
    expect(service.disableShuffle(b), [b, secondA, c]);
  });

  test('queue synchronization preserves original order and appends additions',
      () {
    final a = _Item('a', 'a');
    final b = _Item('b', 'b');
    final c = _Item('c', 'c');
    final added = _Item('d', 'd');
    final service = ShuffleService<_Item>();
    service.enableShuffle([a, b, c], b);

    service.synchronizeQueue([b, c, a, added]);

    expect(service.originalQueue, [a, b, c, added]);
    expect(service.shuffledQueue, [b, c, a, added]);
  });

  test('Connect restoration keeps positional duplicate backing order', () {
    final firstA = _Item('a', 'first');
    final secondA = _Item('a', 'second');
    final c = _Item('c', 'c');
    final resolved = <_Item>[c, firstA, secondA];
    final service = ShuffleService<_Item>()
      ..restoreShuffled(
        originalQueue: <_Item>[firstA, secondA, c],
        shuffledQueue: resolved,
      );

    expect(service.backingOrderFor(resolved), <int>[1, 2, 0]);
    final restored = service.disableShuffle(c);
    expect(restored.map((item) => item.occurrence),
        <String>['first', 'second', 'c']);
    expect(service.indexOfOccurrence(restored, c), 2);
  });
}

class _Item {
  const _Item(this.id, this.occurrence);

  final String id;
  final String occurrence;

  @override
  bool operator ==(Object other) => other is _Item && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$id:$occurrence';
}
