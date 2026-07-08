/// Shared text normalization for library search.
///
/// Every client (mobile, desktop, TV) searches through the same pipeline so a
/// query behaves identically everywhere. For each field/query we derive:
///
/// - a canonical form (`norm`): lowercased, diacritic-folded,
///   punctuation-cleaned, whitespace-collapsed;
/// - a Latin transliteration (`translit`) when the text contains Cyrillic,
///   so `kino` can find `Кино`;
/// - (query side only) keyboard-layout alternates, so `rbyj` — `кино` typed
///   on a QWERTY layout — can find `Кино`.
library;

/// Normalized, match-ready representation of a text field or query token.
class SearchText {
  const SearchText({
    required this.norm,
    required this.words,
    required this.translit,
    required this.translitWords,
    required this.hasCyrillic,
  });

  /// Canonical searchable form (lowercase, folded, punctuation-cleaned).
  final String norm;

  /// [norm] split on whitespace.
  final List<String> words;

  /// Latin transliteration of [norm]; equals [norm] when there is no
  /// Cyrillic to transliterate.
  final String translit;

  /// [translit] split on whitespace.
  final List<String> translitWords;

  /// Whether [norm] contains Cyrillic characters.
  final bool hasCyrillic;

  bool get isEmpty => norm.isEmpty;

  static const empty = SearchText(
    norm: '',
    words: <String>[],
    translit: '',
    translitWords: <String>[],
    hasCyrillic: false,
  );
}

/// Normalizes field text and queries into [SearchText], and generates the
/// query-side transliteration / keyboard-layout variants.
class SearchNormalizer {
  SearchNormalizer._();

  // Normalization is re-run on every field of every item per search, so
  // results are memoized; library strings repeat across searches. The cache
  // is cleared wholesale when it grows past the cap (simple + deterministic).
  static final Map<String, SearchText> _cache = <String, SearchText>{};
  static const int _cacheLimit = 50000;

  /// Apostrophe-family characters are deleted (not replaced by a space) so
  /// `dont` matches `Don't`. Covers ASCII, right single quote, modifier
  /// letter apostrophe, backtick and acute accent.
  static final RegExp _apostrophes =
      RegExp("['’ʼ`´]");

  /// Everything that is not a Unicode letter or digit becomes a word break.
  static final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// Combining diacritical marks (covers NFD-decomposed accents).
  static final RegExp _combiningMarks = RegExp('[̀-ͯ]');

  static final RegExp _cyrillic = RegExp('[Ѐ-ӿ]');

  static SearchText of(String raw) {
    final cached = _cache[raw];
    if (cached != null) return cached;
    final result = _normalize(raw);
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[raw] = result;
    return result;
  }

  static SearchText _normalize(String raw) {
    final norm = normalizeString(raw);
    if (norm.isEmpty) return SearchText.empty;
    final hasCyrillic = _cyrillic.hasMatch(norm);
    final translit = hasCyrillic ? transliterate(norm) : norm;
    return SearchText(
      norm: norm,
      words: norm.split(' '),
      translit: translit,
      translitWords: hasCyrillic ? translit.split(' ') : const <String>[],
      hasCyrillic: hasCyrillic,
    );
  }

  /// Canonicalizes [raw]: lowercase → recompose NFD Cyrillic й/ё → fold
  /// diacritics → strip remaining combining marks → drop apostrophes →
  /// non-letters/digits to spaces → collapse whitespace.
  static String normalizeString(String raw) {
    var text = raw.toLowerCase();
    // macOS tags/filenames are often NFD-decomposed. For Latin, stripping
    // the combining mark below *is* the fold (e + combining acute → e).
    // Cyrillic й/ё are distinct letters though, so recompose them first
    // instead of degrading й to и.
    text = text
        .replaceAll('й', 'й') // и + breve → й
        .replaceAll('ё', 'ё'); // е + diaeresis → ё
    final folded = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      folded.write(_foldMap[char] ?? char);
    }
    text = folded.toString().replaceAll(_combiningMarks, '');
    text = text.replaceAll(_apostrophes, '');
    return text.replaceAll(_nonWord, ' ').trim();
  }

  /// Cyrillic → Latin transliteration (informal romanization). Applied to
  /// normalized text; non-Cyrillic characters pass through unchanged.
  static String transliterate(String norm) {
    final out = StringBuffer();
    for (final rune in norm.runes) {
      final char = String.fromCharCode(rune);
      out.write(_translitMap[char] ?? char);
    }
    // ъ/ь map to a space, which can leave double spaces behind.
    return out.toString().replaceAll(_nonWord, ' ').trim();
  }

  /// Keyboard-layout alternates of a raw query token: the same keystrokes
  /// interpreted on the other layout (QWERTY ↔ ЙЦУКЕН). Returns normalized,
  /// non-empty forms that differ from the token's own normalized form.
  static List<String> layoutAlternates(String rawToken) {
    final lower = rawToken.toLowerCase();
    final base = normalizeString(rawToken);
    final alternates = <String>[];
    for (final map in [_qwertyToJcuken, _jcukenToQwerty]) {
      final mapped = StringBuffer();
      var changed = false;
      for (final rune in lower.runes) {
        final char = String.fromCharCode(rune);
        final replacement = map[char];
        if (replacement != null) changed = true;
        mapped.write(replacement ?? char);
      }
      if (!changed) continue;
      final normMapped = normalizeString(mapped.toString());
      if (normMapped.isEmpty || normMapped == base) continue;
      if (!alternates.contains(normMapped)) alternates.add(normMapped);
    }
    return alternates;
  }

  /// Diacritic folding for precomposed characters. Decomposed input is
  /// handled by [_combiningMarks] stripping instead. Includes ё → е, the
  /// standard Russian search equivalence.
  static const Map<String, String> _foldMap = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'ă': 'a', 'ą': 'a',
    'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c',
    'ď': 'd', 'đ': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e',
    'ę': 'e', 'ě': 'e',
    'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
    'ĥ': 'h', 'ħ': 'h',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i',
    'į': 'i', 'ı': 'i',
    'ĵ': 'j',
    'ķ': 'k',
    'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ł': 'l',
    'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ŏ': 'o', 'ő': 'o',
    'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
    'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's',
    'ţ': 't', 'ť': 't', 'ŧ': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u',
    'ů': 'u', 'ű': 'u', 'ų': 'u',
    'ŵ': 'w',
    'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
    'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'þ': 'th',
    'ё': 'е',
  };

  static const Map<String, String> _translitMap = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh',
    'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
    'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
    'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ъ': ' ',
    'ы': 'y', 'ь': ' ', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  };

  /// Physical-key mapping between the US QWERTY and Russian ЙЦУКЕН layouts.
  /// Punctuation keys are included because they carry letters on the other
  /// layout (e.g. `;` is `ж`), and must be mapped before punctuation is
  /// stripped by normalization.
  static const Map<String, String> _qwertyToJcuken = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г',
    'i': 'ш', 'o': 'щ', 'p': 'з', '[': 'х', ']': 'ъ',
    'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о',
    'k': 'л', 'l': 'д', ';': 'ж', "'": 'э',
    'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю', '`': 'ё',
  };

  static const Map<String, String> _jcukenToQwerty = {
    'й': 'q', 'ц': 'w', 'у': 'e', 'к': 'r', 'е': 't', 'н': 'y', 'г': 'u',
    'ш': 'i', 'щ': 'o', 'з': 'p', 'х': '[', 'ъ': ']',
    'ф': 'a', 'ы': 's', 'в': 'd', 'а': 'f', 'п': 'g', 'р': 'h', 'о': 'j',
    'л': 'k', 'д': 'l', 'ж': ';', 'э': "'",
    'я': 'z', 'ч': 'x', 'с': 'c', 'м': 'v', 'и': 'b', 'т': 'n', 'ь': 'm',
    'б': ',', 'ю': '.', 'ё': '`',
  };
}
