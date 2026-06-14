import 'dart:convert';
import 'dart:typed_data';

/// Repairs "mojibake": UTF-8 bytes that a tag reader decoded as Latin-1,
/// turning multi-byte characters into sequences like `Ã¡` (should be `á`) or
/// `Ð¢Ð°` (should be `Та`).
///
/// This happens routinely with ID3 tags: legacy ID3v1 fields are defined as
/// ISO-8859-1, but encoders frequently stuff raw UTF-8 bytes into them, and
/// readers then hand those bytes back decoded as Latin-1.
///
/// Returns the corrected text, or `null` when [str] is not Latin-1-misread
/// UTF-8 and must be left untouched.
///
/// Tolerates a single incomplete multi-byte sequence at the very end of the
/// string. ID3v1 stores text in fixed-width 30-byte fields, which routinely
/// truncate UTF-8 text mid-character. Without this tolerance, the dangling
/// trailing byte would defeat the repair and the raw mojibake would leak into
/// stored metadata (e.g. `Ð¢Ð°ÑÑÑÐ½Ð° ...` instead of `Татьяна ...`).
String? repairLatin1Mojibake(String str) {
  if (str.isEmpty) return null;

  // Latin-1-misread UTF-8 only ever yields code points <= 0xFF. Anything above
  // that is already proper Unicode (e.g. a correctly decoded UTF-16 frame) and
  // must not be round-tripped.
  for (final unit in str.codeUnits) {
    if (unit > 0xFF) return null;
  }

  final bytes = latin1.encode(str);

  // Happy path: the bytes form completely valid UTF-8.
  try {
    final decoded = utf8.decode(bytes);
    // If decoding doesn't change anything (e.g. pure ASCII), it wasn't mojibake.
    return decoded == str ? null : decoded;
  } on FormatException {
    // Fall through: this may be mojibake truncated mid-character.
  }

  // Drop a single incomplete trailing multi-byte sequence and retry strictly.
  final trimmed = _stripIncompleteTrailingUtf8(bytes);
  if (trimmed == null) return null;
  try {
    final decoded = utf8.decode(trimmed);
    // Only accept the trimmed repair when it actually recovered real multi-byte
    // characters. This prevents genuine Latin-1 text that merely ends in an
    // accented letter (e.g. "café", "Beyoncé") from being mistaken for
    // truncated mojibake and clipped to "caf" / "Beyonc".
    final recoveredMultiByte = decoded.runes.any((r) => r > 0x7F);
    return recoveredMultiByte ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Returns [bytes] without a single incomplete UTF-8 multi-byte sequence at the
/// end, or `null` when the tail is not a recoverable truncation (i.e. the final
/// sequence is already complete, or the bytes are not valid UTF-8 structure).
Uint8List? _stripIncompleteTrailingUtf8(Uint8List bytes) {
  var i = bytes.length - 1;
  var continuationBytes = 0;

  // Walk back over UTF-8 continuation bytes (10xxxxxx) to find the lead byte.
  while (i >= 0 && (bytes[i] & 0xC0) == 0x80) {
    continuationBytes++;
    i--;
    if (continuationBytes > 3) return null; // longer than any valid sequence
  }
  if (i < 0) return null;

  final lead = bytes[i];
  final int expectedContinuations;
  if ((lead & 0x80) == 0x00) {
    expectedContinuations = 0; // ASCII lead: trailing sequence is complete
  } else if ((lead & 0xE0) == 0xC0) {
    expectedContinuations = 1;
  } else if ((lead & 0xF0) == 0xE0) {
    expectedContinuations = 2;
  } else if ((lead & 0xF8) == 0xF0) {
    expectedContinuations = 3;
  } else {
    return null; // not a valid lead byte
  }

  // The trailing sequence is already complete, so truncation is not the
  // problem here; leave the bytes alone.
  if (continuationBytes == expectedContinuations) return null;

  // Drop the incomplete lead + its (too few) continuation bytes.
  return bytes.sublist(0, i);
}
