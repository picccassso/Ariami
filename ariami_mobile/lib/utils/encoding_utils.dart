import 'dart:convert';

/// Utility functions for fixing text encoding issues
class EncodingUtils {
  /// Fixes mojibake (UTF-8 bytes misread as Latin-1)
  ///
  /// This handles cases where ID3 tags or other metadata sources claim Latin-1
  /// encoding but actually contain UTF-8 bytes, resulting in garbled text.
  ///
  /// Handles various character sets:
  /// - Western European (Spanish, French, etc.): Ã, Â patterns
  /// - Korean (Hangul): ì, í, î patterns (3-byte UTF-8)
  /// - Japanese/Chinese (CJK): Similar multi-byte patterns
  ///
  /// Example: "ì¼ê³± ë²ì§¸ ê°ê°" → "일곱 번째 감각"
  static String? fixEncoding(String? value) {
    if (value == null) return null;
    if (value.isEmpty) return value;

    try {
      // Always attempt to fix encoding by re-encoding as Latin-1 and decoding as UTF-8
      // This will fix mojibake for all character sets (Western, Korean, Japanese, Chinese, etc.)
      final latin1Bytes = latin1.encode(value);
      final fixedStr = utf8.decode(latin1Bytes, allowMalformed: true);

      // Only use the fixed version if it's different and appears to be valid
      // Check if the fix actually changed something and produced valid UTF-8
      if (fixedStr != value && fixedStr.isNotEmpty) {
        // Verify the fixed string doesn't contain replacement characters
        // which would indicate invalid UTF-8
        if (!fixedStr.contains('�')) {
          return fixedStr;
        }
      }

      return value;
    } catch (e) {
      // If conversion fails, return original
      return value;
    }
  }
}
