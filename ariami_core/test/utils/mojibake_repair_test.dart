import 'dart:convert';

import 'package:ariami_core/utils/mojibake_repair.dart';
import 'package:test/test.dart';

void main() {
  group('repairLatin1Mojibake', () {
    test('repairs fully-intact UTF-8-as-Latin-1 mojibake (Cyrillic)', () {
      // What a tag reader hands back when it decodes UTF-8 bytes as Latin-1.
      final mojibake = latin1.decode(utf8.encode('Татьяна Куртукова'));
      expect(mojibake, isNot('Татьяна Куртукова'));

      expect(repairLatin1Mojibake(mojibake), 'Татьяна Куртукова');
    });

    test('repairs mojibake truncated mid-character by a 30-byte ID3v1 field',
        () {
      // This is the exact production failure: "Одного" by Татьяна Куртукова.
      // The ID3v1 artist field is 30 bytes and the artist's UTF-8 is 33 bytes,
      // so the final character ("в") is cut in half, leaving a dangling lead
      // byte. The old repair rejected this because the dangling byte decoded to
      // U+FFFD, letting raw mojibake win the "longest value" merge.
      final fullUtf8 = utf8.encode('Татьяна Куртукова'); // 33 bytes
      final id3v1Field = fullUtf8.sublist(0, 30); // truncated mid-"в"
      final mojibake = latin1.decode(id3v1Field);

      expect(repairLatin1Mojibake(mojibake), 'Татьяна Куртуко');
    });

    test('repairs mojibake containing C1 control bytes (title path)', () {
      // "Одного" — the leading "О" is U+041E => UTF-8 D0 9E, whose 0x9E byte is
      // a C1 control. The repair must run before any control-stripping.
      final mojibake = latin1.decode(utf8.encode('Одного'));
      expect(repairLatin1Mojibake(mojibake), 'Одного');
    });

    test('repairs Western European mojibake', () {
      expect(repairLatin1Mojibake(latin1.decode(utf8.encode('Beyoncé'))),
          'Beyoncé');
      expect(repairLatin1Mojibake('Ã¡'), 'á');
    });

    test('leaves already-correct Unicode untouched', () {
      // Correctly decoded UTF-16 frames contain code points > 0xFF.
      expect(repairLatin1Mojibake('Татьяна Куртукова'), isNull);
      expect(repairLatin1Mojibake('Одного'), isNull);
    });

    test('does not clip genuine Latin-1 text ending in an accented letter', () {
      // Guards against false positives: "café"/"Beyoncé" must not be mistaken
      // for truncated mojibake and clipped to "caf"/"Beyonc".
      expect(repairLatin1Mojibake('café'), isNull);
      expect(repairLatin1Mojibake('Beyoncé'), isNull);
    });

    test('leaves plain ASCII and empty strings untouched', () {
      expect(repairLatin1Mojibake('G-Eazy'), isNull);
      expect(repairLatin1Mojibake(''), isNull);
    });
  });
}
