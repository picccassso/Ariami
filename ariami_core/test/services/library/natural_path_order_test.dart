import 'package:test/test.dart';

import 'package:ariami_core/services/library/natural_path_order.dart';

void main() {
  List<String> sorted(List<String> input) =>
      List<String>.from(input)..sort(compareNaturalPath);

  test('orders 3-digit tracks after 2-digit ones (the 100+ case)', () {
    expect(
      sorted([
        '/p/118 - A.mp3',
        '/p/12 - B.mp3',
        '/p/120 - C.mp3',
        '/p/02 - D.mp3',
        '/p/100 - E.mp3',
      ]),
      [
        '/p/02 - D.mp3',
        '/p/12 - B.mp3',
        '/p/100 - E.mp3',
        '/p/118 - A.mp3',
        '/p/120 - C.mp3',
      ],
    );
  });

  test('handles unpadded numbering', () {
    expect(
      sorted(['/p/10 x.mp3', '/p/2 y.mp3', '/p/1 z.mp3']),
      ['/p/1 z.mp3', '/p/2 y.mp3', '/p/10 x.mp3'],
    );
  });

  test('numerically equal runs with different padding stay deterministic',
      () {
    expect(
      sorted(['/p/007.mp3', '/p/7.mp3']),
      ['/p/7.mp3', '/p/007.mp3'],
      reason: 'less-padded run sorts first on a tie',
    );
  });

  test('non-numeric names fall back to plain ordering', () {
    expect(
      sorted(['/p/zebra.mp3', '/p/alpha.mp3', '/p/mid.mp3']),
      ['/p/alpha.mp3', '/p/mid.mp3', '/p/zebra.mp3'],
    );
  });

  test('numbers deeper in the path are compared numerically too', () {
    expect(
      sorted(['/p/disc10/01.mp3', '/p/disc2/01.mp3']),
      ['/p/disc2/01.mp3', '/p/disc10/01.mp3'],
    );
  });

  test('prefix relationships and equality behave like compareTo', () {
    expect(compareNaturalPath('/p/a.mp3', '/p/a.mp3'), 0);
    expect(compareNaturalPath('/p/a', '/p/a.mp3'), lessThan(0));
    expect(compareNaturalPath('/p/a.mp3', '/p/a'), greaterThan(0));
  });
}
