/// Indexed batch matcher resolving Spotify `(title, albumArtist, album)` keys
/// onto library song ids.
///
/// Indexes are built ONCE from the catalog; matching is a tiered cascade:
/// exact normalized title+artist key -> album-anchored -> restricted fuzzy
/// (rarest-title-token candidate generation, gated on artist agreement) ->
/// unmatched. Matched results always carry the LIBRARY's title/artist/album
/// strings so imported plays roll up together with live-tracked stats instead
/// of fragmenting on Spotify-side spelling (e.g. "Beyoncé" -> "Beyonce").
library;

import 'dart:math' as math;

import '../../search/search_normalizer.dart';
import '../credited_artist_splitter.dart';
import 'spotify_import_models.dart';

/// Concrete [TrackMatcher] over an in-memory library catalog.
class LibraryTrackMatcher implements TrackMatcher {
  /// Builds all indexes once; [match] is then O(1)-ish per key.
  LibraryTrackMatcher(List<LibraryCatalogEntry> catalog) {
    for (final entry in catalog) {
      _byId[entry.songId] = entry;
      final variants = _artistVariants(entry.artist);
      final titleCredits = _featArtists(entry.title);
      if (titleCredits != null && titleCredits.isNotEmpty) {
        variants.addAll(_artistVariants(titleCredits));
      }
      _variantsById[entry.songId] = variants;
      final normAlbum = entry.album == null ? '' : _norm(entry.album!);
      for (final normTitle in _libraryTitleVariants(entry)) {
        for (final variant in variants) {
          _exactByTitleArtist
              .putIfAbsent('$normTitle|||$variant', () => <String>[])
              .add(entry.songId);
        }
        if (normAlbum.isNotEmpty) {
          _byTitleAlbum
              .putIfAbsent('$normTitle|||$normAlbum', () => <String>[])
              .add(entry.songId);
        }
        for (final word in normTitle.split(' ')) {
          if (word.isNotEmpty) {
            _byTitleWord.putIfAbsent(word, () => <String>{}).add(entry.songId);
          }
        }
      }
    }
  }

  static const int _fuzzyCandidateCap = 60;
  static const double _fuzzyThreshold = 0.6;
  static const double _ambiguousScoreMargin = 0.05;
  static const int _levCap = 2;

  /// Words marking a trailing title suffix as a non-base recording
  /// ("(Live)", " - 2012 Remaster", "[Radio Edit]", ...). Multi-word tags
  /// from the spec ("radio edit", "single version", "re-recorded") are
  /// covered word-wise by 'edit'/'version' etc.
  static const Set<String> _variantTags = <String>{
    'live',
    'remaster',
    'remastered',
    'remix',
    'edit',
    'extended',
    'acoustic',
    'demo',
    'mono',
    'version',
    'mix',
    'mixes',
    'deluxe',
    'soundtrack',
    'bonus',
    'recording',
    'performance',
  };

  static final RegExp _featSuffixRe = RegExp(
    r'\s*(?:[\(\[]\s*(?:(?:feat\.?|ft\.?|featuring|with)\b|&)\s*[^\)\]]*[\)\]]|\b(?:feat\.?|ft\.?|featuring)\b\s.*)$',
    caseSensitive: false,
  );
  static final RegExp _featArtistsRe = RegExp(
    r'[\(\[]\s*(?:feat|ft|featuring)\b\.?\s+([^\)\]]+)[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _featCreditBlockRe = RegExp(
    r'\s*[\(\[]\s*(?:feat|ft|featuring)\b\.?\s+[^\)\]]+[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _expandedAcronymRe = RegExp(
    r'^([A-Za-z](?:\s*\.\s*[A-Za-z]){1,})\s*\([^\)]+\)\s*(?:pt\.?\s*\d+)?$',
    caseSensitive: false,
  );
  static final RegExp _versionNumberRe =
      RegExp(r'^(?:\d+|[ivxlcdm]+)$', caseSensitive: false);
  static const Set<String> _distinctRecordingWords = <String>{
    'instrumental',
    'karaoke',
    'cappella',
    'acappella',
  };
  static final RegExp _parenSuffixRe =
      RegExp(r'^(.*?)\s*[\(\[]([^\)\]]*)[\)\]]\s*$');
  static final RegExp _dashSuffixRe = RegExp(r'^(.*?)\s+-\s+([^-]+)$');
  static final RegExp _artistTitlePrefixRe =
      RegExp(r'^(.+?)\s+[-\u2013\u2014]\s+(.+)$');
  static final RegExp _asciiLetterRe = RegExp('[A-Za-z]');
  static final RegExp _letterRe = RegExp(r'\p{L}', unicode: true);
  static final RegExp _wrappedSuffixRe =
      RegExp(r'^(.*?)\s*[\(\[]([^\)\]]+)[\)\]]\s*$');

  final Map<String, LibraryCatalogEntry> _byId =
      <String, LibraryCatalogEntry>{};
  final Map<String, List<String>> _exactByTitleArtist =
      <String, List<String>>{};
  final Map<String, List<String>> _byTitleAlbum = <String, List<String>>{};
  final Map<String, Set<String>> _byTitleWord = <String, Set<String>>{};
  final Map<String, Set<String>> _variantsById = <String, Set<String>>{};

  final CreditedArtistSplitter _splitter = CreditedArtistSplitter();

  @override
  TrackMatch match(SpotifyTrackKey key) {
    final titleVariants = _titleVariants(key.title);
    final albumArtistNorm = _norm(key.albumArtist);
    // "Various Artists" (or empty) carries no artist signal: title/album only.
    final artistAbsent =
        albumArtistNorm.isEmpty || albumArtistNorm == 'various artists';
    final artistCandidates =
        artistAbsent ? const <String>{} : _spotifyArtistCandidates(key);

    // Tier 1: exact normalized title+artist key.
    if (artistCandidates.isNotEmpty) {
      for (var i = 0; i < titleVariants.length; i++) {
        final hits = <String>{};
        for (final artist in artistCandidates) {
          final ids = _exactByTitleArtist['${titleVariants[i]}|||$artist'];
          if (ids != null) hits.addAll(ids);
        }
        if (hits.isEmpty) continue;
        // Raw title matched verbatim on both sides -> full confidence; a
        // stripped variant (feat./remaster/live/...) folds for less.
        final hasRawLibraryTitle =
            hits.any((id) => _norm(_byId[id]!.title) == titleVariants[i]);
        final confidence = i == 0 && hasRawLibraryTitle ? 1.0 : 0.9;
        return _resolveMultiple(hits, key, MatchTier.exact, confidence);
      }
    }

    // Tier 2: album-anchored (artist string drifted, title+album agree).
    final normAlbum = key.album == null ? '' : _norm(key.album!);
    if (normAlbum.isNotEmpty) {
      final ids = _albumBucket(titleVariants, normAlbum);
      if (ids.isNotEmpty) {
        return _resolveMultiple(ids, key, MatchTier.albumAnchored, 0.9);
      }
    }

    // Tier 3: restricted fuzzy over a small candidate set.
    final fuzzy =
        _fuzzyMatch(titleVariants, artistCandidates, albumArtistNorm);
    if (fuzzy != null) return fuzzy;

    // Unmatched: carry the Spotify strings so the play still reads sensibly.
    return TrackMatch(
      songId: null,
      title: key.title,
      artist: key.albumArtist,
      album: key.album,
      confidence: 0,
      tier: MatchTier.unmatched,
    );
  }

  @override
  Map<SpotifyTrackKey, TrackMatch> matchAll(Iterable<SpotifyTrackKey> keys) {
    final results = <SpotifyTrackKey, TrackMatch>{};
    for (final key in keys) {
      results[key] ??= match(key);
    }
    return results;
  }

  /// Resolves a set of title+artist (or title+album) [hits] to a single match.
  ///
  /// Most collisions in a real library are the SAME recording owned in several
  /// places (studio + deluxe + a personal compilation folder). Those are not a
  /// "which song did they mean" ambiguity — every copy is the same song by the
  /// same artist, so play/artist stats are identical whichever is chosen. We
  /// therefore pick the copy whose album best matches the Spotify album (so the
  /// canonical album wins over a "sleep time" folder) and return a CONFIDENT
  /// match, keeping the other copies as [TrackMatch.alternateSongIds].
  ///
  /// Only hits that are genuinely different songs sharing this key (same title,
  /// but a different full artist credit — e.g. a solo vs a feat. version) stay
  /// [MatchTier.ambiguous] for review.
  TrackMatch _resolveMultiple(
      Set<String> hits, SpotifyTrackKey key, MatchTier tier, double confidence) {
    if (hits.length == 1) return _libraryMatch(hits.first, tier, confidence);
    final normAlbum = key.album == null ? '' : _norm(key.album!);
    final rawSpotifyTitle = _norm(key.title);

    // Prefer a verbatim normalized title over a hit created by stripping
    // "Live", "Remix", "Album Version", etc. This keeps a Spotify base
    // recording on the library's base copy when both it and a variant exist.
    final rawTitleHits =
        hits.where((id) => _norm(_byId[id]!.title) == rawSpotifyTitle).toSet();
    final candidates = rawTitleHits.isEmpty ? hits : rawTitleHits;

    // Rank by album agreement with Spotify (exact > containment > token
    // overlap > none), deterministic songId tiebreak so re-imports are stable.
    final ordered = candidates.toList()
      ..sort((a, b) {
        final byAlbum =
            _albumScore(b, normAlbum).compareTo(_albumScore(a, normAlbum));
        return byAlbum != 0 ? byAlbum : a.compareTo(b);
      });
    final lowerPriority = hits.difference(candidates).toList()
      ..sort((a, b) {
        final byAlbum =
            _albumScore(b, normAlbum).compareTo(_albumScore(a, normAlbum));
        return byAlbum != 0 ? byAlbum : a.compareTo(b);
      });
    List<String> alternatesAfter(String chosen) => <String>[
          ...ordered.where((id) => id != chosen),
          ...lowerPriority.where((id) => id != chosen),
        ];

    if (candidates.length == 1) {
      return _libraryMatch(candidates.first, tier, confidence, lowerPriority);
    }

    // A single copy whose album EXACTLY matches Spotify is an unambiguous pick
    // even across different songs.
    if (normAlbum.isNotEmpty) {
      final exact =
          candidates.where((id) => _albumScore(id, normAlbum) == 3).toList();
      if (exact.length == 1) {
        return _libraryMatch(
            exact.first, tier, confidence, alternatesAfter(exact.first));
      }
    }

    if (_allSameSong(candidates)) {
      return _libraryMatch(
          ordered.first, tier, confidence, alternatesAfter(ordered.first));
    }
    return _libraryMatch(ordered.first, MatchTier.ambiguous, 0.5,
        alternatesAfter(ordered.first));
  }

  /// Album agreement of song [songId] with a normalized Spotify album:
  /// 3 = equal, 2 = one contains the other (handles "Album - X"/"X (Deluxe)"),
  /// 1 = shared word, 0 = none/unknown.
  int _albumScore(String songId, String spotifyAlbumNorm) {
    if (spotifyAlbumNorm.isEmpty) return 0;
    final album = _byId[songId]?.album;
    if (album == null || album.trim().isEmpty) return 0;
    final lib = _norm(album);
    if (lib.isEmpty) return 0;
    if (lib == spotifyAlbumNorm) return 3;
    if (lib.contains(spotifyAlbumNorm) || spotifyAlbumNorm.contains(lib)) {
      return 2;
    }
    final libWords = lib.split(' ').where((w) => w.isNotEmpty).toSet();
    final spWords = spotifyAlbumNorm.split(' ').where((w) => w.isNotEmpty).toSet();
    return libWords.intersection(spWords).isNotEmpty ? 1 : 0;
  }

  /// True when every hit is the same recording: identical normalized title and
  /// identical normalized full artist credit.
  bool _allSameSong(Iterable<String> ids) {
    String? signature;
    for (final id in ids) {
      final e = _byId[id];
      if (e == null) return false;
      final sig = '${_norm(e.title)}|||${_norm(e.artist)}';
      signature ??= sig;
      if (sig != signature) return false;
    }
    return true;
  }

  Set<String> _albumBucket(List<String> titleVariants, String normAlbum) {
    final ids = <String>{};
    for (final title in titleVariants) {
      final list = _byTitleAlbum['$title|||$normAlbum'];
      if (list != null) ids.addAll(list);
    }
    return ids;
  }

  /// Fuzzy candidate generation from the rarest title token (never a
  /// full-library scan), scored on title similarity and gated on artist
  /// agreement.
  TrackMatch? _fuzzyMatch(List<String> titleVariants,
      Set<String> artistCandidates, String albumArtistNorm) {
    if (artistCandidates.isEmpty || titleVariants.isEmpty) return null;
    final words = <String>{};
    for (final title in titleVariants) {
      words.addAll(title.split(' ').where((w) => w.isNotEmpty));
    }
    final postings = <Set<String>>[
      for (final word in words)
        if (_byTitleWord[word] != null) _byTitleWord[word]!,
    ]..sort((a, b) => a.length.compareTo(b.length));
    if (postings.isEmpty) return null;
    var candidates = postings.first;
    for (final posting in postings.skip(1)) {
      if (candidates.length <= _fuzzyCandidateCap) break;
      final narrowed = candidates.intersection(posting);
      if (narrowed.isNotEmpty) candidates = narrowed;
    }
    if (candidates.length > _fuzzyCandidateCap) {
      final sorted = candidates.toList()..sort();
      candidates = sorted.take(_fuzzyCandidateCap).toSet();
    }

    final queryTitle = titleVariants.first;
    final scored = <MapEntry<String, double>>[];
    for (final songId in candidates) {
      if (!_artistAgrees(songId, artistCandidates, albumArtistNorm)) continue;
      final score = _titleScore(queryTitle, _norm(_byId[songId]!.title));
      if (score >= _fuzzyThreshold) scored.add(MapEntry(songId, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.value.compareTo(a.value));
    final strong = scored
        .where((e) => scored.first.value - e.value < _ambiguousScoreMargin)
        .map((e) => e.key)
        .toList();
    if (strong.length > 1) {
      return _libraryMatch(
          strong.first, MatchTier.ambiguous, 0.5, strong.skip(1).toList());
    }
    return _libraryMatch(scored.first.key, MatchTier.fuzzy,
        scored.first.value.clamp(0.0, 0.85));
  }

  /// Artist agreement gate: shared normalized variant (exact-norm or
  /// credited-key overlap) or substring containment of the raw norms.
  bool _artistAgrees(String songId, Set<String> spotifyCandidates,
      String spotifyRawNorm) {
    final entryVariants = _variantsById[songId] ?? const <String>{};
    if (entryVariants.any(spotifyCandidates.contains)) return true;
    for (final entry in entryVariants) {
      if (entry.length < 5) continue;
      for (final spotify in spotifyCandidates) {
        if (spotify.length >= 5 && _levenshtein(entry, spotify, 1) <= 1) {
          return true;
        }
      }
    }
    final entryRawNorm = _norm(_byId[songId]!.artist);
    return entryRawNorm.isNotEmpty &&
        spotifyRawNorm.isNotEmpty &&
        (entryRawNorm.contains(spotifyRawNorm) ||
            spotifyRawNorm.contains(entryRawNorm));
  }

  /// Token-overlap (Jaccard) plus a small Levenshtein bonus (distance <=
  /// [_levCap]) on the normalized title strings.
  double _titleScore(String a, String b) {
    if (a == b) return 1.0;
    if (_hasConflictingVersionNumbers(a, b)) return 0.0;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    final shorterWords = shorter.split(' ').where((w) => w.isNotEmpty).length;
    final containsWholeTitle = longer.startsWith('$shorter ') ||
        longer.endsWith(' $shorter') ||
        longer.contains(' $shorter ');
    if (containsWholeTitle && (shorter.length >= 8 || shorterWords >= 3)) {
      final extraWords = longer
          .replaceFirst(shorter, '')
          .split(' ')
          .where((word) => word.isNotEmpty)
          .toSet();
      if (extraWords.any(_distinctRecordingWords.contains) ||
          (extraWords.isNotEmpty &&
              extraWords.every(_versionNumberRe.hasMatch))) {
        return 0.0;
      }
      return 0.85;
    }
    final wordsA = a.split(' ').toSet();
    final wordsB = b.split(' ').toSet();
    final union = wordsA.union(wordsB).length;
    final jaccard =
        union == 0 ? 0.0 : wordsA.intersection(wordsB).length / union;
    final distance = _levenshtein(a, b, _levCap);
    final levScore = distance > _levCap
        ? 0.0
        : 1.0 - distance / math.max(a.length, b.length);
    return 0.75 * jaccard + 0.25 * levScore;
  }

  bool _hasConflictingVersionNumbers(String a, String b) {
    Set<String> numbers(String value) => value
        .split(' ')
        .where(_versionNumberRe.hasMatch)
        .map((number) => number.toLowerCase())
        .toSet();

    final aNumbers = numbers(a);
    final bNumbers = numbers(b);
    return aNumbers.isNotEmpty &&
        bNumbers.isNotEmpty &&
        !aNumbers.containsAll(bNumbers) &&
        !bNumbers.containsAll(aNumbers);
  }

  /// Levenshtein distance, early-exiting with [_levCap] + 1 once it is clear
  /// the distance exceeds [cap].
  int _levenshtein(String a, String b, int cap) {
    if ((a.length - b.length).abs() > cap) return cap + 1;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final curr = List<int>.filled(b.length + 1, 0)..[0] = i;
      var rowMin = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final value = math.min(
            math.min(prev[j] + 1, curr[j - 1] + 1), prev[j - 1] + cost);
        curr[j] = value;
        if (value < rowMin) rowMin = value;
      }
      if (rowMin > cap) return cap + 1;
      prev = curr;
    }
    return prev[b.length];
  }

  /// Normalized title variants to try, most specific first: the raw
  /// normalized title, plus forms with a trailing "(feat. X)" and/or a
  /// variant-tagged suffix ("(Live)", " - Remaster") removed.
  List<String> _titleVariants(String rawTitle) {
    final variants = <String>[];
    final seen = <String>{};
    void add(String title) {
      final n = _norm(title);
      if (n.isNotEmpty && seen.add(n)) variants.add(n);
      final numbered = n.replaceAllMapped(
        RegExp(r'\bno (?=\d)'),
        (_) => 'number ',
      );
      if (numbered != n && seen.add(numbered)) variants.add(numbered);
    }

    add(rawTitle);
    final withoutCreditBlock =
        rawTitle.replaceAll(_featCreditBlockRe, '').trim();
    if (withoutCreditBlock != rawTitle) add(withoutCreditBlock);
    final expandedAcronym = _expandedAcronymRe.firstMatch(rawTitle);
    if (expandedAcronym != null) add(expandedAcronym.group(1)!);
    final noFeat = _stripFeatSuffix(rawTitle);
    final noTag = _stripVariantSuffix(rawTitle);
    if (noFeat != rawTitle) {
      add(noFeat);
      final both = _stripVariantSuffix(noFeat);
      if (both != noFeat) add(both);
    }
    if (noTag != rawTitle) {
      add(noTag);
      final both = _stripFeatSuffix(noTag);
      if (both != noTag) add(both);
    }
    for (final variant in _multilingualTitleVariants(rawTitle)) {
      add(variant);
    }
    return variants;
  }

  /// Library titles need the same suffix handling as Spotify titles. Without
  /// this, a Spotify base title cannot reach a local "(feat. X)", "Album
  /// Version", or bilingual-tagged title even though the reverse direction
  /// already works.
  List<String> _libraryTitleVariants(LibraryCatalogEntry entry) {
    final variants = _titleVariants(entry.title);
    final prefixed = _artistTitlePrefixRe.firstMatch(entry.title);
    if (prefixed != null) {
      final prefix = _norm(prefixed.group(1)!);
      if (_artistVariants(entry.artist).contains(prefix)) {
        for (final variant in _titleVariants(prefixed.group(2)!)) {
          if (!variants.contains(variant)) variants.add(variant);
        }
      }
    }
    return variants;
  }

  /// Produces the separately tagged language forms used by common music tags,
  /// for example "오아시스 (Oasis)", "으르렁 Growl", and "The Star 星".
  /// Artist agreement still gates every resulting match.
  List<String> _multilingualTitleVariants(String title) {
    final variants = <String>[];
    final wrapped = _wrappedSuffixRe.firstMatch(title);
    if (wrapped != null &&
        _usesDifferentScripts(wrapped.group(1)!, wrapped.group(2)!)) {
      variants.add(wrapped.group(1)!.trim());
      variants.add(wrapped.group(2)!.trim());
    }

    final words = title.split(RegExp(r'\s+'));
    final ascii = words.where(_hasAsciiLetters).join(' ').trim();
    final nonAscii = words.where(_hasNonAsciiLetters).join(' ').trim();
    if (ascii.isNotEmpty &&
        nonAscii.isNotEmpty &&
        _usesDifferentScripts(ascii, nonAscii)) {
      variants.add(ascii);
      variants.add(nonAscii);
    }
    return variants;
  }

  bool _usesDifferentScripts(String a, String b) =>
      (_hasAsciiLetters(a) && _hasNonAsciiLetters(b)) ||
      (_hasNonAsciiLetters(a) && _hasAsciiLetters(b));

  bool _hasAsciiLetters(String value) => _asciiLetterRe.hasMatch(value);

  bool _hasNonAsciiLetters(String value) => value.runes.any(
      (rune) => rune > 0x7f && _letterRe.hasMatch(String.fromCharCode(rune)));

  /// Artist lookup candidates for a Spotify key: the album artist's variants
  /// plus the featured artist(s) lifted out of a "(feat. X)" title suffix.
  Set<String> _spotifyArtistCandidates(SpotifyTrackKey key) {
    final candidates = _artistVariants(key.albumArtist);
    final feat = _featArtists(key.title);
    if (feat != null && feat.isNotEmpty) {
      candidates.addAll(_artistVariants(feat));
    }
    return candidates;
  }

  /// The normalized artist variants one artist string indexes/queries under:
  /// raw norm, primary artist (feat. stripped, first comma segment), each
  /// [CreditedArtist.key] from the splitter, and de-"the" forms of each.
  Set<String> _artistVariants(String rawArtist) {
    final variants = <String>{};
    void addNorm(String value) {
      final searchable = SearchNormalizer.of(value);
      if (searchable.norm.isNotEmpty) variants.add(searchable.norm);
      if (searchable.hasCyrillic && searchable.translit.isNotEmpty) {
        variants.add(searchable.translit);
      }
    }

    addNorm(rawArtist);
    addNorm(_primaryArtist(rawArtist));
    for (final credited in _splitter.split(rawArtist)) {
      addNorm(credited.key);
    }
    for (final languageForm in _multilingualTitleVariants(rawArtist)) {
      addNorm(languageForm);
    }
    for (final variant in variants.toList()) {
      if (variant.startsWith('the ') && variant.length > 4) {
        variants.add(variant.substring(4));
      }
      final compact = variant.replaceAll(' ', '');
      if (compact.length >= 4 && compact != variant) variants.add(compact);
    }
    return variants;
  }

  /// Primary artist: trailing "(feat. …)"/"feat. …"/"ft. …" removed, then the
  /// first comma segment. The splitter's credited keys keep protected names
  /// like "Tyler, the Creator" intact alongside this.
  String _primaryArtist(String rawArtist) {
    var s = rawArtist.replaceAll(_featSuffixRe, '');
    final comma = s.indexOf(',');
    if (comma > 0) s = s.substring(0, comma);
    return s.trim();
  }

  String _stripFeatSuffix(String title) =>
      title.replaceAll(_featSuffixRe, '').trim();

  /// The "X" of a trailing "(feat. X)"/"[ft. X]" title suffix, or null.
  String? _featArtists(String title) =>
      _featArtistsRe.firstMatch(title)?.group(1)?.trim();

  /// Removes trailing "(...)"/"[...]"/" - ..." suffixes while they carry a
  /// variant tag ([_variantTags]); returns [title] unchanged otherwise.
  String _stripVariantSuffix(String title) {
    var t = title;
    while (true) {
      final next = _stripOneVariantSuffix(t);
      if (next == t) return t;
      t = next;
    }
  }

  String _stripOneVariantSuffix(String title) {
    final paren = _parenSuffixRe.firstMatch(title);
    if (paren != null &&
        paren.group(1)!.trim().isNotEmpty &&
        _hasVariantTag(paren.group(2)!)) {
      return paren.group(1)!.trim();
    }
    final dash = _dashSuffixRe.firstMatch(title);
    if (dash != null &&
        dash.group(1)!.trim().isNotEmpty &&
        _hasVariantTag(dash.group(2)!)) {
      return dash.group(1)!.trim();
    }
    return title;
  }

  bool _hasVariantTag(String suffix) => _norm(suffix)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .any(_variantTags.contains);

  /// Emits a match carrying the LIBRARY entry's strings (never Spotify's).
  TrackMatch _libraryMatch(String songId, MatchTier tier, double confidence,
      [List<String> alternateSongIds = const <String>[]]) {
    final entry = _byId[songId]!;
    return TrackMatch(
      songId: songId,
      title: entry.title,
      artist: entry.artist,
      album: entry.album,
      albumId: entry.albumId,
      confidence: confidence,
      tier: tier,
      alternateSongIds: alternateSongIds,
    );
  }

  String _norm(String raw) => SearchNormalizer.of(raw).norm;
}
