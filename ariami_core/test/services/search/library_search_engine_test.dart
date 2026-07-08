import 'package:ariami_core/services/search/search.dart';
import 'package:test/test.dart';

/// A minimal stand-in for a client model (song/album/playlist).
class _Item {
  const _Item(this.id, this.title, [this.artist, this.albumTitle]);
  final String id;
  final String title;
  final String? artist;
  final String? albumTitle;
}

List<SearchField> _fieldsOf(_Item item) => [
      SearchField(item.title, isPrimary: true),
      if (item.artist != null) SearchField(item.artist!),
      if (item.albumTitle != null) SearchField(item.albumTitle!),
    ];

List<String> _search(String query, List<_Item> items, {int? limit}) {
  final ranked = LibrarySearchEngine.rank(
    SearchQuery.parse(query),
    items,
    _fieldsOf,
    limit: limit,
  );
  return [for (final item in ranked) item.id];
}

void main() {
  group('SearchNormalizer', () {
    test('lowercases, folds diacritics and strips punctuation', () {
      expect(SearchNormalizer.normalizeString('  BEYONCÉ!!  '), 'beyonce');
      expect(SearchNormalizer.normalizeString("Don't Stop"), 'dont stop');
      expect(SearchNormalizer.normalizeString('Motörhead'), 'motorhead');
      expect(SearchNormalizer.normalizeString('AC/DC'), 'ac dc');
    });

    test('handles NFD-decomposed input (Latin fold, Cyrillic recompose)', () {
      // 'e' + combining acute — as produced by macOS filenames/tags.
      expect(SearchNormalizer.normalizeString('Beyonce\u0301'), 'beyonce');
      // 'и' + combining breve must recompose to й, not degrade to и,
      // and NFD input must normalize identically to NFC input.
      expect(SearchNormalizer.normalizeString('\u043a\u0438\u0306\u043d\u043e'),
          '\u043a\u0439\u043d\u043e');
    });

    test('folds ё to е (standard Russian search equivalence)', () {
      expect(SearchNormalizer.normalizeString('Полёт'), 'полет');
    });

    test('transliterates Cyrillic to informal Latin', () {
      expect(SearchNormalizer.of('Кино').translit, 'kino');
      expect(SearchNormalizer.of('Виктор Цой').translit, 'viktor tsoy');
      expect(SearchNormalizer.of('Жук').translit, 'zhuk');
      expect(SearchNormalizer.of('Щука').translit, 'shchuka');
    });

    test('produces keyboard-layout alternates both ways', () {
      // QWERTY keystrokes meant for the Russian layout…
      expect(SearchNormalizer.layoutAlternates('rbyj'), contains('кино'));
      // …and Russian keystrokes meant for the US layout.
      expect(SearchNormalizer.layoutAlternates('вщте'), contains('dont'));
    });

    test('maps punctuation keys that carry letters on the other layout', () {
      // 'q;br' → й, ж, и, к — ';' must map before punctuation stripping.
      expect(SearchNormalizer.layoutAlternates('q;br'), contains('йжик'));
    });
  });

  group('LibrarySearchEngine matching', () {
    const kino = _Item('kino', 'Группа крови', 'Кино');
    const tsoy = _Item('tsoy', 'Кончится лето', 'Виктор Цой');
    const stronger = _Item('stronger', 'Stronger', 'Kanye West', 'Graduation');
    const dontStop = _Item('dont-stop', 'Don’t Stop', 'Queen');
    const beyonce = _Item('halo', 'Halo', 'Beyoncé');
    const motorhead = _Item('ace', 'Ace of Spades', 'Motörhead');

    const library = [kino, tsoy, stronger, dontStop, beyonce, motorhead];

    test('case-insensitive Latin and Cyrillic', () {
      expect(_search('STRONGER', library), ['stronger']);
      expect(_search('кино', library), ['kino']);
      expect(_search('КИНО', library), ['kino']);
      expect(_search('Кино', library), ['kino']);
    });

    test('multi-word cross-field query (kanye stronger)', () {
      expect(_search('kanye stronger', library), ['stronger']);
    });

    test('song findable by album title', () {
      expect(_search('graduation', library), ['stronger']);
    });

    test('transliteration: kino finds Кино', () {
      expect(_search('kino', library), ['kino']);
    });

    test('transliteration: viktor tsoy finds Виктор Цой', () {
      expect(_search('viktor tsoy', library), ['tsoy']);
    });

    test('keyboard layout: rbyj finds Кино', () {
      expect(_search('rbyj', library), ['kino']);
    });

    test('reverse direction: Cyrillic query finds Latin field', () {
      // Query typed in Cyrillic against a Latin-tagged library.
      expect(_search('стронгер', library), ['stronger']);
    });

    test('diacritic folding: beyonce finds Beyoncé', () {
      expect(_search('beyonce', library), ['halo']);
      expect(_search('motorhead', library), ['ace']);
    });

    test('punctuation-insensitive: dont stop finds Don’t Stop', () {
      expect(_search('dont stop', library), ['dont-stop']);
      expect(_search("don't stop", library), ['dont-stop']);
    });

    test('Cyrillic fuzzy typo', () {
      // 'группо' — one substitution from 'группа'.
      expect(_search('группо', library), ['kino']);
    });

    test('Latin fuzzy typo', () {
      expect(_search('stringer', library), ['stronger']);
    });

    test('a token matching nothing rejects the item', () {
      expect(_search('kanye nonexistentword', library), isEmpty);
    });

    test('empty and whitespace queries return nothing', () {
      expect(_search('', library), isEmpty);
      expect(_search('   ', library), isEmpty);
    });
  });

  group('LibrarySearchEngine ranking', () {
    test('tiers order: exact, field prefix, token prefix, substring, fuzzy, '
        'assisted', () {
      const items = [
        _Item('assisted', 'Кино', 'Артист'), // via translit of the field
        _Item('fuzzy', 'Kina', 'Artist'),
        _Item('substring', 'Akinom', 'Artist'),
        _Item('token-prefix', 'Big Kinofilm Poster', 'Artist'),
        _Item('field-prefix', 'Kino Club Anthem', 'Artist'),
        _Item('exact', 'Kino', 'Artist'),
      ];

      expect(_search('kino', items), [
        'exact',
        'field-prefix',
        'token-prefix',
        'substring',
        'fuzzy',
        'assisted',
      ]);
    });

    test('exact title outranks incidental substring', () {
      const items = [
        _Item('substr', 'Big Mirrors Poster'),
        _Item('exact', 'Mirrors'),
      ];

      expect(_search('mirrors', items), ['exact', 'substr']);
    });

    test('title match ranks above artist-only match within a tier', () {
      const items = [
        _Item('by-artist', 'Some Song', 'Halo'),
        _Item('by-title', 'Halo', 'Beyoncé'),
      ];

      expect(_search('halo', items), ['by-title', 'by-artist']);
    });

    test('ranking is stable: ties keep input order', () {
      const items = [
        _Item('first', 'Halo', 'A'),
        _Item('second', 'Halo', 'B'),
      ];

      expect(_search('halo', items), ['first', 'second']);
    });

    test('limit caps results after ranking', () {
      const items = [
        _Item('substr', 'Big Mirrors Poster'),
        _Item('exact', 'Mirrors'),
      ];

      expect(_search('mirrors', items, limit: 1), ['exact']);
    });
  });
}
