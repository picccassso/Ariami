import 'package:ariami_mobile/models/repeat_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RepeatMode.forNewSongSelection', () {
    test('turns repeat-one into repeat-all', () {
      expect(RepeatMode.one.forNewSongSelection, RepeatMode.all);
    });

    test('keeps repeat-all and repeat-off unchanged', () {
      expect(RepeatMode.all.forNewSongSelection, RepeatMode.all);
      expect(RepeatMode.none.forNewSongSelection, RepeatMode.none);
    });
  });

  group('RepeatMode.allowsBoundaryRestart', () {
    test('is enabled for repeat modes only', () {
      expect(RepeatMode.none.allowsBoundaryRestart, isFalse);
      expect(RepeatMode.all.allowsBoundaryRestart, isTrue);
      expect(RepeatMode.one.allowsBoundaryRestart, isTrue);
    });
  });
}
