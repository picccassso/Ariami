import 'package:ariami_core/services/stats/spotify_import/library_track_matcher.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';
import 'package:test/test.dart';

void main() {
  LibraryTrackMatcher matcherOf(List<LibraryCatalogEntry> catalog) =>
      LibraryTrackMatcher(catalog);

  group('exact tier', () {
    test('diacritics fold and result carries LIBRARY strings', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
          songId: 's-bey',
          title: 'Halo',
          artist: 'Beyonce',
          album: 'I Am... Sasha Fierce',
          albumId: 'alb-1',
        ),
      ]);
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Halo',
        albumArtist: 'Beyoncé',
        album: 'I Am... Sasha Fierce',
      ));
      expect(result.isMatched, isTrue);
      expect(result.songId, 's-bey');
      expect(result.tier, MatchTier.exact);
      expect(result.confidence, 1.0);
      expect(result.artist, 'Beyonce');
      expect(result.title, 'Halo');
      expect(result.album, 'I Am... Sasha Fierce');
      expect(result.albumId, 'alb-1');
    });

    test('"(feat. X)" in Spotify title vs feat. in library artist tag', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
          songId: 's-feat',
          title: 'Song',
          artist: 'A feat. X',
          album: 'Album',
        ),
      ]);
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Song (feat. X)',
        albumArtist: 'A',
        album: 'Album',
      ));
      expect(result.isMatched, isTrue);
      expect(result.songId, 's-feat');
      expect(result.tier, MatchTier.exact);
      expect(result.artist, 'A feat. X');
    });

    test('"A, B" vs "A & B" via credited splitter', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
          songId: 's-collab',
          title: 'Collab',
          artist: 'A, B',
          album: 'Joint',
        ),
      ]);
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Collab',
        albumArtist: 'A & B',
        album: 'Joint',
      ));
      expect(result.isMatched, isTrue);
      expect(result.songId, 's-collab');
      expect(result.artist, 'A, B');
    });

    test('protected name "Tyler, the Creator" is not shredded', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
          songId: 's-tyler',
          title: 'Song A',
          artist: 'Tyler, the Creator',
          album: 'Album',
        ),
        LibraryCatalogEntry(
          songId: 's-creator',
          title: 'Song A',
          artist: 'The Creator',
          album: 'Album',
        ),
      ]);
      final tyler = matcher.match(const SpotifyTrackKey(
        title: 'Song A',
        albumArtist: 'Tyler, the Creator',
        album: 'Album',
      ));
      expect(tyler.songId, 's-tyler');
      expect(tyler.tier, MatchTier.exact);
      // "The Creator" must resolve to the genuinely different artist only,
      // not to a shredded "the Creator" fragment of "Tyler, the Creator".
      final creator = matcher.match(const SpotifyTrackKey(
        title: 'Song A',
        albumArtist: 'The Creator',
        album: 'Album',
      ));
      expect(creator.songId, 's-creator');
      expect(creator.tier, MatchTier.exact);
    });

    test('"The X" vs "X" both resolve; "The The" still works', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(songId: 's-1', title: 'Tune One', artist: 'The X'),
        LibraryCatalogEntry(songId: 's-2', title: 'Tune Two', artist: 'X'),
        LibraryCatalogEntry(
            songId: 's-3', title: 'Tune Three', artist: 'The The'),
      ]);
      expect(
        matcher
            .match(const SpotifyTrackKey(title: 'Tune One', albumArtist: 'X'))
            .songId,
        's-1',
      );
      expect(
        matcher
            .match(
                const SpotifyTrackKey(title: 'Tune Two', albumArtist: 'The X'))
            .songId,
        's-2',
      );
      final theThe = matcher.match(
          const SpotifyTrackKey(title: 'Tune Three', albumArtist: 'The The'));
      expect(theThe.songId, 's-3');
      expect(theThe.tier, MatchTier.exact);
    });

    test('remaster/live Spotify title folds to base recording, lower conf',
        () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
            songId: 's-base', title: 'Song', artist: 'Artist', album: 'Album'),
      ]);
      final remaster = matcher.match(const SpotifyTrackKey(
        title: 'Song (Remastered)',
        albumArtist: 'Artist',
        album: 'Album',
      ));
      expect(remaster.songId, 's-base');
      expect(remaster.confidence, lessThan(1.0));
      final live = matcher.match(const SpotifyTrackKey(
        title: 'Song - Live',
        albumArtist: 'Artist',
        album: 'Album',
      ));
      expect(live.songId, 's-base');
      expect(live.confidence, lessThan(1.0));
      final remix = matcher.match(const SpotifyTrackKey(
        title: 'Song (Club Remix)',
        albumArtist: 'Artist',
        album: 'Album',
      ));
      expect(remix.songId, 's-base');
      expect(remix.confidence, lessThan(1.0));
    });
  });

  group('disambiguation', () {
    final matcher = matcherOf(const [
      LibraryCatalogEntry(
          songId: 's-one',
          title: 'Song',
          artist: 'Artist',
          album: 'Album One'),
      LibraryCatalogEntry(
          songId: 's-two',
          title: 'Song',
          artist: 'Artist',
          album: 'Album Two'),
    ]);

    test('same title+artist on two albums: album agreement disambiguates', () {
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Song',
        albumArtist: 'Artist',
        album: 'Album Two',
      ));
      expect(result.tier, MatchTier.exact);
      expect(result.songId, 's-two');
      expect(result.album, 'Album Two');
    });

    test('without album: same recording in two places -> confident, not review',
        () {
      final result = matcher
          .match(const SpotifyTrackKey(title: 'Song', albumArtist: 'Artist'));
      // Both copies are the same song by the same artist, so this is not a
      // "which song?" ambiguity — it is a confident match with the other copy
      // carried as an alternate.
      expect(result.tier, MatchTier.exact);
      expect(result.isMatched, isTrue);
      expect(result.confidence, 1.0);
      expect({result.songId, ...result.alternateSongIds},
          <String?>{'s-one', 's-two'});
    });

    test('partial album match picks the right copy ("Album Two" contains "Two")',
        () {
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Song',
        albumArtist: 'Artist',
        album: 'Two',
      ));
      expect(result.isMatched, isTrue);
      expect(result.songId, 's-two');
      expect(result.tier, MatchTier.exact);
    });

    test('different songs sharing a title+artist key stay ambiguous', () {
      final m = matcherOf(const [
        LibraryCatalogEntry(
            songId: 'a', title: 'Song', artist: 'Artist', album: 'One'),
        LibraryCatalogEntry(
            songId: 'b', title: 'Song', artist: 'Artist, Guest', album: 'Two'),
      ]);
      // "Artist" matches both via the credited-artist variant, but the two
      // library entries are different credits -> genuine review case.
      final result =
          m.match(const SpotifyTrackKey(title: 'Song', albumArtist: 'Artist'));
      expect(result.tier, MatchTier.ambiguous);
      expect({result.songId, ...result.alternateSongIds}, <String?>{'a', 'b'});
    });
  });

  group('album-anchored tier', () {
    test('"Various Artists" treated as absent: title+album only', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
          songId: 's-va',
          title: 'Anthem',
          artist: 'Some Act',
          album: 'Movie Soundtrack',
        ),
      ]);
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Anthem',
        albumArtist: 'Various Artists',
        album: 'Movie Soundtrack',
      ));
      expect(result.tier, MatchTier.albumAnchored);
      expect(result.songId, 's-va');
      expect(result.artist, 'Some Act');
    });
  });

  group('unmatched', () {
    test('streamed track absent from library keeps Spotify strings', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
            songId: 's-1', title: 'Halo', artist: 'Beyonce', album: 'Album'),
      ]);
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Never Heard',
        albumArtist: 'Ghost Artist',
        album: 'Ghost Album',
      ));
      expect(result.tier, MatchTier.unmatched);
      expect(result.songId, isNull);
      expect(result.isMatched, isFalse);
      expect(result.confidence, 0);
      expect(result.title, 'Never Heard');
      expect(result.artist, 'Ghost Artist');
      expect(result.album, 'Ghost Album');
      expect(result.albumId, isNull);
    });

    test('untagged library entry (filename title): no crash, no match', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
            songId: 's-untagged',
            title: '01 track.mp3',
            artist: 'Unknown Artist'),
      ]);
      final result = matcher.match(const SpotifyTrackKey(
        title: 'Real Song',
        albumArtist: 'Real Artist',
        album: 'Real Album',
      ));
      expect(result.songId, isNull);
      expect(result.tier, MatchTier.unmatched);
    });
  });

  group('matchAll', () {
    test('dedupes keys and matches each unique key', () {
      final matcher = matcherOf(const [
        LibraryCatalogEntry(
            songId: 's-bey', title: 'Halo', artist: 'Beyonce'),
      ]);
      const hit = SpotifyTrackKey(title: 'Halo', albumArtist: 'Beyoncé');
      const miss = SpotifyTrackKey(title: 'Nope', albumArtist: 'Nobody');
      final results = matcher.matchAll([hit, hit, miss, hit, miss]);
      expect(results.length, 2);
      expect(results[hit]!.songId, 's-bey');
      expect(results[hit]!.artist, 'Beyonce');
      expect(results[miss]!.songId, isNull);
      expect(results[miss]!.tier, MatchTier.unmatched);
    });
  });
}
