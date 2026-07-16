import 'package:ariami_mobile/models/album_stats.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/artist_stats.dart';
import 'package:ariami_mobile/models/song_stats.dart';
import 'package:ariami_mobile/services/stats/stats_artwork_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final album = AlbumModel(
    id: 'album-current',
    title: 'The Album',
    artist: 'The Artist',
    coverArt: '/api/custom-cover/album-current',
    songCount: 1,
    duration: 180,
  );
  final song = SongModel(
    id: 'song-1',
    title: 'The Song',
    artist: 'The Artist',
    albumId: album.id,
    duration: 180,
  );
  late StatsArtworkResolver resolver;

  setUp(() {
    resolver = StatsArtworkResolver(albums: [album], songs: [song]);
  });

  test('track stats prefer the current library album cache identity', () {
    final artwork = resolver.forSong(const SongStats(
      songId: 'song-1',
      albumId: 'album-stale',
      playCount: 2,
      totalTime: Duration(minutes: 6),
    ));

    expect(artwork.cacheId, 'album-current');
    expect(artwork.artworkUrl, '/api/custom-cover/album-current');
  });

  test('stale track ids recover the current album by title and artist', () {
    final artwork = resolver.forSong(const SongStats(
      songId: 'song-from-old-server-state',
      songTitle: ' the song ',
      songArtist: 'THE ARTIST',
      playCount: 2,
      totalTime: Duration(minutes: 6),
    ));

    expect(artwork.cacheId, 'album-current');
    expect(artwork.artworkUrl, '/api/custom-cover/album-current');
  });

  test('metadata match supersedes a stale recorded album id', () {
    final artwork = resolver.forSong(const SongStats(
      songId: 'song-from-old-server-state',
      songTitle: 'The Song',
      songArtist: 'The Artist',
      albumId: 'album-from-old-server-state',
      playCount: 2,
      totalTime: Duration(minutes: 6),
    ));

    expect(artwork.cacheId, 'album-current');
  });

  test('album name rollups recover a missing album id from local metadata', () {
    final artwork = resolver.forAlbum(const AlbumStats(
      albumId: '',
      albumName: ' the album ',
      albumArtist: 'THE ARTIST',
      playCount: 2,
      totalTime: Duration(minutes: 6),
      uniqueSongsCount: 1,
    ));

    expect(artwork.cacheId, 'album-current');
    expect(artwork.artworkUrl, '/api/custom-cover/album-current');
  });

  test('artist stats recover artwork through a current library song', () {
    final artwork = resolver.forArtist(const ArtistStats(
      artistName: 'The Artist',
      playCount: 2,
      totalTime: Duration(minutes: 6),
      randomAlbumId: 'album-stale',
      uniqueSongsCount: 1,
    ));

    expect(artwork.cacheId, 'album-current');
  });

  test('unresolved rows receive distinct non-empty cache identities', () {
    final first = resolver.forAlbum(const AlbumStats(
      albumId: '',
      albumName: 'Missing One',
      playCount: 1,
      totalTime: Duration(minutes: 1),
      uniqueSongsCount: 1,
    ));
    final second = resolver.forAlbum(const AlbumStats(
      albumId: '',
      albumName: 'Missing Two',
      playCount: 1,
      totalTime: Duration(minutes: 1),
      uniqueSongsCount: 1,
    ));

    expect(first.cacheId, isNotEmpty);
    expect(second.cacheId, isNotEmpty);
    expect(first.cacheId, isNot(second.cacheId));
  });
}
