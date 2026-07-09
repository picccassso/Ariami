import 'package:ariami_core/utils/text_sanitizer.dart';

/// One artist credited on a song, derived from the raw display artist string.
///
/// The raw string on songs/events is never modified — it stays the display
/// truth (e.g. "Kanye West, Big Sean, Pusha T, 2 Chainz"). Credits exist so
/// stats can attribute the full play/time to each collaborator individually.
class CreditedArtist {
  /// Normalized grouping key (see [normalizeArtistKey]).
  final String key;

  /// Best display label, original casing/spacing preserved.
  final String display;

  /// Position in the credit list; 0 is the primary artist.
  final int ordinal;

  const CreditedArtist({
    required this.key,
    required this.display,
    required this.ordinal,
  });

  @override
  String toString() => 'CreditedArtist($ordinal: $display)';
}

/// Normalize an artist (or album) name into a stable grouping key so
/// visually-identical names from different sources match. Mirrors the
/// normalization the mobile/desktop clients already apply at read time:
/// strips invisible characters, lowercases, trims, collapses internal
/// whitespace, and unifies unicode hyphen/dash variants to a plain hyphen.
String normalizeArtistKey(String name) {
  var s = sanitizeTagText(name).toLowerCase();
  // Map unicode hyphen/dash variants (hyphen, non-breaking hyphen, figure
  // dash, en/em dash, minus sign) to a plain ASCII hyphen.
  s = s.replaceAll(RegExp('[\\u2010-\\u2015\\u2212]'), '-');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s;
}

/// Splits a raw display artist string into individually credited artists.
///
/// "Kanye West, Big Sean, Pusha T, 2 Chainz" credits all four artists;
/// "Tyler, the Creator" stays one artist because it is on the protected-name
/// allowlist. Splitting is derivation only — the original string is always
/// preserved for display, and each credited artist receives the FULL play and
/// FULL listened time (credit is not divided between collaborators).
class CreditedArtistSplitter {
  /// Names that legitimately contain separator characters and must never be
  /// shredded. Matched case-insensitively with word boundaries, so they are
  /// also protected when embedded in a longer credit list
  /// ("Tyler, the Creator, Kanye West" → 2 artists).
  static const Set<String> defaultProtectedNames = {
    'tyler, the creator',
    'earth, wind & fire',
    'ac/dc',
    'simon & garfunkel',
    'blood, sweat & tears',
    'crosby, stills & nash',
    'crosby, stills, nash & young',
    'emerson, lake & palmer',
    'peter, paul and mary',
    'hall & oates',
    'daryl hall & john oates',
    'ike & tina turner',
    'sonny & cher',
    'captain & tennille',
    'brooks & dunn',
    'big & rich',
    'she & him',
    'iron & wine',
    'angus & julia stone',
    'mumford & sons',
    'florence & the machine',
    'kool & the gang',
    'echo & the bunnymen',
    'siouxsie & the banshees',
    'nick cave & the bad seeds',
    'tom petty & the heartbreakers',
    'huey lewis & the news',
    'hootie & the blowfish',
    'bob marley & the wailers',
    'derek & the dominos',
    "booker t. & the m.g.'s",
    'martha & the vandellas',
    'joan jett & the blackhearts',
    'sly & the family stone',
    'gladys knight & the pips',
    'smokey robinson & the miracles',
    'diana ross & the supremes',
    'bruce springsteen & the e street band',
    'prince & the revolution',
    'elvis costello & the attractions',
  };

  /// Separators that delimit collaborating artists. `,` and `;` split with or
  /// without surrounding spaces; the word separators (feat./ft./featuring,
  /// vs, with, x, &) require whitespace on both sides so names like
  /// "Lil Nas X" or "AT&T Sessions" aren't cut mid-word.
  static final RegExp _separators = RegExp(
    r'\s*[,;]\s*|\s+(?:featuring|feat\.?|ft\.?|vs\.?|with|x|&)\s+',
    caseSensitive: false,
  );

  /// Protected names, longest first so overlapping entries (e.g. the two
  /// Crosby, Stills line-ups) match the most specific name.
  final List<String> _protectedNames;

  CreditedArtistSplitter({Set<String> extraProtectedNames = const {}})
      : _protectedNames = <String>[
          ...defaultProtectedNames,
          ...extraProtectedNames.map((name) => name.toLowerCase().trim()),
        ]..sort((a, b) => b.length.compareTo(a.length));

  /// Splits [rawArtist] into credited artists, order-stable and deduplicated
  /// by normalized key. Returns an empty list only when the input is
  /// null/blank — any real string yields at least one credit.
  List<CreditedArtist> split(String? rawArtist) {
    if (rawArtist == null) return const [];
    final cleaned = sanitizeTagText(rawArtist);
    if (cleaned.isEmpty) return const [];

    // Mask protected names with placeholders so the separator pass cannot
    // shred them, remembering the original (display-cased) text.
    final protectedSpans = <String>[];
    var working = cleaned;
    var lower = working.toLowerCase();
    for (final name in _protectedNames) {
      var searchFrom = 0;
      while (searchFrom < lower.length) {
        final index = lower.indexOf(name, searchFrom);
        if (index < 0) break;
        final end = index + name.length;
        final boundedBefore =
            index == 0 || !_isWordChar(lower.codeUnitAt(index - 1));
        final boundedAfter =
            end >= lower.length || !_isWordChar(lower.codeUnitAt(end));
        if (!boundedBefore || !boundedAfter) {
          searchFrom = index + 1;
          continue;
        }
        final placeholder = '\u0002${protectedSpans.length}\u0002';
        protectedSpans.add(working.substring(index, end));
        working = working.substring(0, index) +
            placeholder +
            working.substring(end);
        lower = working.toLowerCase();
        searchFrom = index + placeholder.length;
      }
    }

    final credits = <String, CreditedArtist>{};
    for (final rawSegment in working.split(_separators)) {
      var segment = rawSegment.replaceAllMapped(
        RegExp('\u0002(\\d+)\u0002'),
        (match) => protectedSpans[int.parse(match.group(1)!)],
      );
      segment = _trimWrapping(segment);
      if (segment.isEmpty) continue;
      final key = normalizeArtistKey(segment);
      if (key.isEmpty || credits.containsKey(key)) continue;
      credits[key] = CreditedArtist(
        key: key,
        display: segment,
        ordinal: credits.length,
      );
    }
    return credits.values.toList();
  }

  static bool _isWordChar(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0x41 && codeUnit <= 0x5a) || // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7a) || // a-z
        codeUnit > 0x7f; // any non-ASCII letter
  }

  /// Trims whitespace plus stray wrapping brackets left behind when a credit
  /// like "(feat. X)" is split apart.
  static String _trimWrapping(String value) {
    var s = value.trim();
    while (s.isNotEmpty && '([{'.contains(s[0])) {
      s = s.substring(1).trimLeft();
    }
    while (s.isNotEmpty && ')]}'.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    return s;
  }
}
