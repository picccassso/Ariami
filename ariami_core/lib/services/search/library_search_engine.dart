/// Shared, deterministic library-search engine used by the mobile, desktop
/// and TV clients. Matching and ranking live here so a query behaves the
/// same on every platform; clients only describe which text fields each of
/// their model types exposes.
library;

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
  SearchField(String raw, {this.isPrimary = false})
      : text = SearchNormalizer.of(raw);

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

  /// Whether [fields] match [query] at any tier. For order-preserving
  /// filters (find-in-page style surfaces) that want the engine's matching —
  /// normalization, transliteration, layout correction, fuzz — without its
  /// ranking.
  static bool matches(SearchQuery query, List<SearchField> fields) {
    if (query.isEmpty) return false;
    return _matchItem(query, fields) != null;
  }

  static _ItemMatch? _matchItem(SearchQuery query, List<SearchField> fields) {
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
      final best = _bestTokenMatch(token, fields);
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
    List<SearchField> fields,
  ) {
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
        _directKind(token.base, text.norm, text.words),
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
              _directKind(token.base, text.translit, text.translitWords) !=
                  null;
        }
        if (!assisted && token.translit != null) {
          // Cyrillic query vs Latin field (кино → kino).
          assisted =
              _directKind(token.translit!, text.norm, text.words) != null;
        }
        if (!assisted) {
          for (final alternate in token.alternates) {
            if (_directKind(alternate, text.norm, text.words) != null ||
                (text.hasCyrillic &&
                    _directKind(
                          alternate,
                          text.translit,
                          text.translitWords,
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
    List<String> words,
  ) {
    if (token.isEmpty || norm.isEmpty) return null;
    for (final word in words) {
      if (word.startsWith(token)) return SearchMatchTier.tokenPrefix;
    }
    if (norm.contains(token)) return SearchMatchTier.substring;
    if (_fuzzyMatches(token, words)) return SearchMatchTier.fuzzy;
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
