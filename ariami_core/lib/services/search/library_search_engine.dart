/// Shared, deterministic library-search engine used by the mobile, desktop
/// and TV clients. Matching and ranking live here so a query behaves the
/// same on every platform; clients only describe which text fields each of
/// their model types exposes.
library;

import 'dart:collection';

import 'search_normalizer.dart';

/// Relevance tiers, strongest first. An item's tier is the weakest tier any
/// query token needed (every token must match somewhere for the item to
/// match at all).
enum SearchMatchTier {
  /// The whole normalized query equals a whole field.
  exact(5),

  /// The whole normalized query is a prefix of a field.
  fieldPrefix(4),

  /// Every token is a whole word, or a prefix of a word, in some field.
  tokenPrefix(3),

  /// Every token appears as a substring of some field.
  substring(2),

  /// Every token matches, but at least one only within edit distance 1–2 of
  /// a field word.
  fuzzy(1),

  /// Every token matches, but at least one only via transliteration
  /// (`kino` → `кино`) or keyboard-layout correction (`rbyj` → `кино`).
  assisted(0);

  const SearchMatchTier(this.rank);
  final int rank;
}

/// One searchable text field of an item. [isPrimary] marks the item's own
/// name (song/album title, playlist name) so that, within a tier, name
/// matches rank above matches on secondary fields like artist.
class SearchField {
  SearchField(String raw, {this.isPrimary = false, bool cache = true})
      : text = SearchNormalizer.of(raw, cache: cache);

  const SearchField.prepared(this.text, {this.isPrimary = false});

  final SearchText text;
  final bool isPrimary;
}

/// A parsed query: normalized phrase + per-token match variants. Build once
/// per query (e.g. per keystroke) and reuse across the songs/albums/playlists
/// passes.
class SearchQuery {
  SearchQuery._(this.phrase, this.tokens);

  factory SearchQuery.parse(String rawQuery) {
    final phrase = SearchNormalizer.normalizeString(rawQuery);
    final tokens = <SearchQueryToken>[];
    for (final rawToken in rawQuery.trim().split(RegExp(r'\s+'))) {
      if (rawToken.isEmpty) continue;
      final token = SearchQueryToken.parse(rawToken);
      if (token != null) tokens.add(token);
    }
    return SearchQuery._(phrase, tokens);
  }

  final String phrase;
  final List<SearchQueryToken> tokens;

  bool get isEmpty => phrase.isEmpty || tokens.isEmpty;
}

class SearchQueryToken {
  SearchQueryToken._(this.base, this.translit, this.alternates);

  static SearchQueryToken? parse(String rawToken) {
    final base = SearchNormalizer.of(rawToken);
    // A token can normalize away entirely (e.g. pure punctuation): the
    // keystrokes may still mean something on the other layout, so alternates
    // are computed from the raw token either way.
    final alternates = SearchNormalizer.layoutAlternates(rawToken);
    if (base.isEmpty && alternates.isEmpty) return null;
    final translit = base.hasCyrillic ? base.translit : null;
    return SearchQueryToken._(base.norm, translit, alternates);
  }

  /// Normalized token as typed.
  final String base;

  /// Transliteration of a Cyrillic token, to try against Latin fields.
  final String? translit;

  /// Keyboard-layout alternates of the token.
  final List<String> alternates;
}

/// Match/rank engine over client-supplied items.
class LibrarySearchEngine {
  LibrarySearchEngine._();

  /// Ranks [items] against [query]. Non-matching items are dropped; matching
  /// items are ordered by tier, then primary-field (name) hits before
  /// secondary-only hits, then original list order (stable). [limit] caps the
  /// returned list where a UI expects caps.
  static List<T> rank<T>(
    SearchQuery query,
    Iterable<T> items,
    List<SearchField> Function(T item) fieldsOf, {
    int? limit,
  }) {
    if (query.isEmpty) return <T>[];

    final matches = <_RankedItem<T>>[];
    var index = 0;
    for (final item in items) {
      final match = _matchItem(query, fieldsOf(item));
      if (match != null) {
        matches.add(_RankedItem(item, match, index));
      }
      index++;
    }

    matches.sort((a, b) {
      if (a.match.tier.rank != b.match.tier.rank) {
        return b.match.tier.rank - a.match.tier.rank;
      }
      if (a.match.primaryHit != b.match.primaryHit) {
        return a.match.primaryHit ? -1 : 1;
      }
      return a.index - b.index;
    });

    final capped =
        limit == null ? matches : matches.take(limit).toList(growable: false);
    return [for (final ranked in capped) ranked.item];
  }

  /// Ranks [items] across metadata fields and plain-text lyrics. Metadata hits
  /// always sort before lyric-only hits; [lyricSnippets] maps an item's ID to
  /// its best matching lyric line when the song matched solely via lyrics or
  /// the lyric match outranks its metadata match.
  static ({List<T> items, Map<String, String> lyricSnippets}) rankWithLyrics<T>(
    SearchQuery query,
    Iterable<T> items, {
    required String Function(T item) idOf,
    required List<SearchField> Function(T item) fieldsOf,
    required String? Function(T item) lyricsOf,
    PreparedLyrics? Function(T item)? preparedLyricsOf,
    int? limit,
  }) {
    if (query.isEmpty) {
      return (items: <T>[], lyricSnippets: const <String, String>{});
    }

    final canMatchLyrics = query.phrase.length >= 3;
    final matches = <_RankedLyricItem<T>>[];
    var index = 0;
    for (final item in items) {
      final metadataMatch = _matchItem(query, fieldsOf(item));
      final lyricMatch = canMatchLyrics
          ? (preparedLyricsOf != null
              ? _matchPreparedLyrics(query, preparedLyricsOf(item))
              : _matchLyrics(query, lyricsOf(item)))
          : null;
      if (metadataMatch != null || lyricMatch != null) {
        matches.add(_RankedLyricItem(item, metadataMatch, lyricMatch, index));
      }
      index++;
    }

    matches.sort((a, b) {
      final aHasMeta = a.metadataMatch != null;
      final bHasMeta = b.metadataMatch != null;
      if (aHasMeta != bHasMeta) {
        return aHasMeta ? -1 : 1;
      }
      if (aHasMeta && bHasMeta) {
        final aMeta = a.metadataMatch!;
        final bMeta = b.metadataMatch!;
        if (aMeta.tier.rank != bMeta.tier.rank) {
          return bMeta.tier.rank - aMeta.tier.rank;
        }
        if (aMeta.primaryHit != bMeta.primaryHit) {
          return aMeta.primaryHit ? -1 : 1;
        }
        final aLyricRank = a.lyricMatch?.tier.rank ?? -1;
        final bLyricRank = b.lyricMatch?.tier.rank ?? -1;
        if (aLyricRank != bLyricRank) {
          return bLyricRank - aLyricRank;
        }
        return a.index - b.index;
      }
      final aLyric = a.lyricMatch!;
      final bLyric = b.lyricMatch!;
      if (aLyric.tier.rank != bLyric.tier.rank) {
        return bLyric.tier.rank - aLyric.tier.rank;
      }
      if (aLyric.singleLine != bLyric.singleLine) {
        return aLyric.singleLine ? -1 : 1;
      }
      return a.index - b.index;
    });

    final capped =
        limit == null ? matches : matches.take(limit).toList(growable: false);
    final lyricSnippets = <String, String>{};
    final resultItems = <T>[];
    for (final ranked in capped) {
      resultItems.add(ranked.item);
      final lyric = ranked.lyricMatch;
      final meta = ranked.metadataMatch;
      if (lyric != null &&
          (meta == null || lyric.tier.rank > meta.tier.rank)) {
        lyricSnippets[idOf(ranked.item)] = lyric.snippet;
      }
    }
    return (items: resultItems, lyricSnippets: lyricSnippets);
  }

  static final RegExp _lineBreak = RegExp(r'\r?\n');
  static final LinkedHashMap<String, PreparedLyrics> _lyricsCache =
      LinkedHashMap<String, PreparedLyrics>();
  static const int _lyricsCacheLimit = 10000;

  /// Splits [rawLyrics] into lines and normalizes the whole text. Per-line
  /// and line-pair fields are built lazily, only for songs whose full text
  /// matches a query (or when [PreparedLyrics.warm] is called).
  static PreparedLyrics? prepareLyrics(String? rawLyrics) {
    if (rawLyrics == null || rawLyrics.trim().isEmpty) return null;
    final rawLines = rawLyrics
        .split(_lineBreak)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (rawLines.isEmpty) return null;
    final lines = [
      for (final line in rawLines) SearchNormalizer.of(line, cache: false),
    ];
    return PreparedLyrics._(rawLines, lines, SearchText.join(lines));
  }

  static PreparedLyrics? _prepareLyricsCached(String rawLyrics) {
    final cached = _lyricsCache.remove(rawLyrics);
    if (cached != null) {
      _lyricsCache[rawLyrics] = cached;
      return cached;
    }
    final prepared = prepareLyrics(rawLyrics);
    if (prepared == null) return null;
    if (_lyricsCache.length >= _lyricsCacheLimit) {
      _lyricsCache.remove(_lyricsCache.keys.first);
    }
    _lyricsCache[rawLyrics] = prepared;
    return prepared;
  }

  static _LyricMatch? _matchLyrics(SearchQuery query, String? rawLyrics) {
    if (rawLyrics == null || rawLyrics.trim().isEmpty) return null;
    return _matchPreparedLyrics(query, _prepareLyricsCached(rawLyrics));
  }

  static _LyricMatch? _matchPreparedLyrics(
    SearchQuery query,
    PreparedLyrics? prepared,
  ) {
    if (prepared == null) return null;
    if (_matchItem(
          query,
          [SearchField.prepared(prepared.fullText)],
          allowFuzzy: false,
        ) ==
        null) {
      return null;
    }
    _LyricMatch? best;
    final lines = prepared._lines;
    for (var i = 0; i < lines.length; i++) {
      final match = _matchItem(query, [SearchField.prepared(lines[i])],
          allowFuzzy: false);
      if (match == null) continue;
      if (best == null || match.tier.rank > best.tier.rank) {
        best = _LyricMatch(match.tier, prepared._rawLines[i], singleLine: true);
        if (best.tier == SearchMatchTier.exact) return best;
      }
    }

    if (query.tokens.length >= 2) {
      final pairs = prepared._pairs;
      for (var i = 0; i < pairs.length; i++) {
        final match = _matchItem(query, [SearchField.prepared(pairs[i])],
            allowFuzzy: false);
        if (match == null) continue;
        if (best == null || match.tier.rank > best.tier.rank) {
          best = _LyricMatch(
            match.tier,
            '${prepared._rawLines[i]} / ${prepared._rawLines[i + 1]}',
            singleLine: false,
          );
          if (best.tier == SearchMatchTier.exact) return best;
        }
      }
    }
    return best;
  }

  /// Whether [fields] match [query] at any tier. For order-preserving
  /// filters (find-in-page style surfaces) that want the engine's matching —
  /// normalization, transliteration, layout correction, fuzz — without its
  /// ranking.
  static bool matches(SearchQuery query, List<SearchField> fields) {
    if (query.isEmpty) return false;
    return _matchItem(query, fields) != null;
  }

  static _ItemMatch? _matchItem(
    SearchQuery query,
    List<SearchField> fields, {
    bool allowFuzzy = true,
  }) {
    // Whole-phrase pass: the strongest tiers require the full query to sit
    // at the start of one field, which per-token matching can't distinguish.
    SearchMatchTier? phraseTier;
    var phrasePrimary = false;
    for (final field in fields) {
      final norm = field.text.norm;
      if (norm.isEmpty) continue;
      SearchMatchTier? tier;
      if (norm == query.phrase) {
        tier = SearchMatchTier.exact;
      } else if (query.phrase.isNotEmpty && norm.startsWith(query.phrase)) {
        tier = SearchMatchTier.fieldPrefix;
      }
      if (tier == null) continue;
      if (phraseTier == null || tier.rank > phraseTier.rank) {
        phraseTier = tier;
        phrasePrimary = field.isPrimary;
      } else if (tier == phraseTier && field.isPrimary) {
        phrasePrimary = true;
      }
    }
    if (phraseTier == SearchMatchTier.exact) {
      return _ItemMatch(SearchMatchTier.exact, phrasePrimary);
    }

    // Per-token pass: every token must match some field; the item's tier is
    // the weakest token's tier.
    SearchMatchTier? weakest;
    var primaryHit = phraseTier != null && phrasePrimary;
    for (final token in query.tokens) {
      final best = _bestTokenMatch(token, fields, allowFuzzy: allowFuzzy);
      if (best == null) {
        // Token failed everywhere; the phrase pass can still carry the item.
        return phraseTier == null
            ? null
            : _ItemMatch(phraseTier, phrasePrimary);
      }
      if (weakest == null || best.tier.rank < weakest.rank) {
        weakest = best.tier;
      }
      if (best.primary) primaryHit = true;
    }
    if (weakest == null) {
      return phraseTier == null ? null : _ItemMatch(phraseTier, phrasePrimary);
    }
    if (phraseTier != null && phraseTier.rank >= weakest.rank) {
      return _ItemMatch(phraseTier, phrasePrimary || primaryHit);
    }
    return _ItemMatch(weakest, primaryHit);
  }

  static _TokenMatch? _bestTokenMatch(
    SearchQueryToken token,
    List<SearchField> fields, {
    bool allowFuzzy = true,
  }) {
    _TokenMatch? best;

    void consider(SearchMatchTier? tier, bool primary) {
      if (tier == null) return;
      if (best == null ||
          tier.rank > best!.tier.rank ||
          (tier == best!.tier && primary && !best!.primary)) {
        best = _TokenMatch(tier, primary);
      }
    }

    for (final field in fields) {
      final text = field.text;
      if (text.isEmpty) continue;

      // Direct match against the canonical form.
      consider(
        _directKind(token.base, text.norm, text.words, allowFuzzy: allowFuzzy),
        field.isPrimary,
      );
      if (best?.tier == SearchMatchTier.tokenPrefix && best!.primary) {
        return best; // Nothing above tokenPrefix exists on the token path.
      }

      // Assisted paths cap at [SearchMatchTier.assisted] regardless of how
      // precisely the variant matched.
      if (best == null || best!.tier == SearchMatchTier.assisted) {
        var assisted = false;
        if (text.hasCyrillic) {
          // Latin query vs transliterated Cyrillic field (kino → кино).
          assisted = assisted ||
              _directKind(
                    token.base,
                    text.translit,
                    text.translitWords,
                    allowFuzzy: allowFuzzy,
                  ) !=
                  null;
        }
        if (!assisted && token.translit != null) {
          // Cyrillic query vs Latin field (кино → kino).
          assisted = _directKind(
                token.translit!,
                text.norm,
                text.words,
                allowFuzzy: allowFuzzy,
              ) !=
              null;
        }
        if (!assisted) {
          for (final alternate in token.alternates) {
            if (_directKind(
                      alternate,
                      text.norm,
                      text.words,
                      allowFuzzy: allowFuzzy,
                    ) !=
                    null ||
                (text.hasCyrillic &&
                    _directKind(
                          alternate,
                          text.translit,
                          text.translitWords,
                          allowFuzzy: allowFuzzy,
                        ) !=
                        null)) {
              assisted = true;
              break;
            }
          }
        }
        if (assisted) {
          consider(SearchMatchTier.assisted, field.isPrimary);
        }
      }
    }
    return best;
  }

  /// Strongest token-path tier for [token] against one searchable string,
  /// or null when it doesn't match at all.
  static SearchMatchTier? _directKind(
    String token,
    String norm,
    List<String> words, {
    bool allowFuzzy = true,
  }) {
    if (token.isEmpty || norm.isEmpty) return null;
    for (final word in words) {
      if (word.startsWith(token)) return SearchMatchTier.tokenPrefix;
    }
    if (norm.contains(token)) return SearchMatchTier.substring;
    if (allowFuzzy && _fuzzyMatches(token, words)) return SearchMatchTier.fuzzy;
    return null;
  }

  /// Typo tolerance: edit distance ≤ 1 for tokens of 4–8 characters and ≤ 2
  /// from 9 characters up, against whole field words or their prefixes.
  /// Shorter tokens get no fuzz — too many false positives.
  static bool _fuzzyMatches(String token, List<String> words) {
    if (token.length < 4) return false;
    final maxDistance = token.length >= 9 ? 2 : 1;
    for (final word in words) {
      if (word.length < 4) continue;
      if ((word.length - token.length).abs() <= maxDistance &&
          _editDistanceAtMost(token, word, maxDistance)) {
        return true;
      }
      if (word.length > token.length &&
          _editDistanceAtMost(
            token,
            word.substring(0, token.length),
            maxDistance,
          )) {
        return true;
      }
    }
    return false;
  }

  static bool _editDistanceAtMost(String a, String b, int maxDistance) {
    if ((a.length - b.length).abs() > maxDistance) return false;
    if (a == b) return true;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      var rowMin = current[0];

      for (var j = 1; j <= b.length; j++) {
        final substitutionCost =
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final insertion = current[j - 1] + 1;
        final deletion = previous[j] + 1;
        final substitution = previous[j - 1] + substitutionCost;
        final distance = insertion < deletion
            ? (insertion < substitution ? insertion : substitution)
            : (deletion < substitution ? deletion : substitution);
        current[j] = distance;
        if (distance < rowMin) rowMin = distance;
      }

      if (rowMin > maxDistance) return false;
      previous = current;
    }

    return previous[b.length] <= maxDistance;
  }
}

class _ItemMatch {
  const _ItemMatch(this.tier, this.primaryHit);
  final SearchMatchTier tier;
  final bool primaryHit;
}

class _TokenMatch {
  const _TokenMatch(this.tier, this.primary);
  final SearchMatchTier tier;
  final bool primary;
}

class _RankedItem<T> {
  const _RankedItem(this.item, this.match, this.index);
  final T item;
  final _ItemMatch match;
  final int index;
}

class _LyricMatch {
  const _LyricMatch(this.tier, this.snippet, {required this.singleLine});
  final SearchMatchTier tier;
  final String snippet;
  final bool singleLine;
}

class PreparedLyrics {
  PreparedLyrics._(this._rawLines, this._lines, this.fullText);
  final List<String> _rawLines;
  final List<SearchText> _lines;
  final SearchText fullText;

  late final List<SearchText> _pairs = [
    for (var i = 0; i + 1 < _lines.length; i++)
      SearchText.join([_lines[i], _lines[i + 1]]),
  ];
}

class _RankedLyricItem<T> {
  const _RankedLyricItem(
    this.item,
    this.metadataMatch,
    this.lyricMatch,
    this.index,
  );
  final T item;
  final _ItemMatch? metadataMatch;
  final _LyricMatch? lyricMatch;
  final int index;
}
