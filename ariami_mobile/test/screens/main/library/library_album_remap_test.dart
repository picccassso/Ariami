import 'package:ariami_mobile/screens/main/library/library_album_remap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remapAlbumKeys', () {
    test('returns unchanged when there is nothing to remap', () {
      final result = remapAlbumKeys(
        pins: {'album:old', 'playlist:p1'},
        recents: {'album:old': DateTime(2026, 1, 1)},
        oldToNew: const {},
      );

      expect(result.hasChanges, isFalse);
      expect(result.pinsChanged, isFalse);
      expect(result.recentsChanged, isFalse);
      expect(result.pins, {'album:old', 'playlist:p1'});
    });

    test('re-points album pins and leaves playlist pins untouched', () {
      final result = remapAlbumKeys(
        pins: {'album:old', 'playlist:p1', 'album:unrelated'},
        recents: const {},
        oldToNew: const {'old': 'new'},
      );

      expect(result.pinsChanged, isTrue);
      expect(result.pins, {'album:new', 'playlist:p1', 'album:unrelated'});
    });

    test('re-points recents keys', () {
      final ts = DateTime(2026, 6, 14);
      final result = remapAlbumKeys(
        pins: const {},
        recents: {'album:old': ts, 'playlist:p1': DateTime(2026, 1, 1)},
        oldToNew: const {'old': 'new'},
      );

      expect(result.recentsChanged, isTrue);
      expect(result.recents['album:new'], ts);
      expect(result.recents.containsKey('album:old'), isFalse);
      expect(result.recents['playlist:p1'], DateTime(2026, 1, 1));
    });

    test('keeps the most recent timestamp when old and new keys both exist', () {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 6, 1);
      final result = remapAlbumKeys(
        pins: const {},
        recents: {'album:old': newer, 'album:new': older},
        oldToNew: const {'old': 'new'},
      );

      expect(result.recents['album:new'], newer);
      expect(result.recents.length, 1);
    });

    test('does not flag changes when no keys match the remap', () {
      final result = remapAlbumKeys(
        pins: {'album:other'},
        recents: {'album:other': DateTime(2026, 1, 1)},
        oldToNew: const {'old': 'new'},
      );

      expect(result.hasChanges, isFalse);
    });
  });
}
