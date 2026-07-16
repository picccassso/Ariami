import '../../models/album_stats.dart';
import '../../models/api_models.dart';
import '../../models/artist_stats.dart';
import '../../models/song_stats.dart';
import '../../utils/artwork_url.dart';

/// A stable cache identity plus the best available server artwork URL.
class StatsArtworkIdentity {
  const StatsArtworkIdentity({
    required this.cacheId,
    required this.artworkUrl,
  });

  final String cacheId;
  final String? artworkUrl;
}

/// Resolves sparse or stale listening-stat artwork metadata against the
/// authoritative locally-synced library.
///
/// Old imports and name-keyed period rollups can omit album IDs, while album
/// IDs can also change after server metadata normalization. Keeping this logic
/// outside the stats widgets makes every stats tab use the same fallback order.
class StatsArtworkResolver {
  StatsArtworkResolver({
    required Iterable<AlbumModel> albums,
    required Iterable<SongModel> songs,
  })  : _albumsById = <String, AlbumModel>{
          for (final album in albums) album.id: album,
        },
        _songsById = <String, SongModel>{
          for (final song in songs) song.id: song,
        } {
    for (final album in _albumsById.values) {
      final titleKey = _normalize(album.title);
      if (titleKey.isEmpty) continue;

      final exactKey = _albumMetadataKey(album.title, album.artist);
      _albumsByMetadata.putIfAbsent(exactKey, () => album);

      final existing = _uniqueAlbumsByTitle[titleKey];
      if (existing == null && !_ambiguousAlbumTitles.contains(titleKey)) {
        _uniqueAlbumsByTitle[titleKey] = album;
      } else if (existing?.id != album.id) {
        _uniqueAlbumsByTitle.remove(titleKey);
        _ambiguousAlbumTitles.add(titleKey);
      }
    }

    for (final song in _songsById.values) {
      final key = _songMetadataKey(song.title, song.artist);
      if (key == _songMetadataKey('', '')) continue;
      _songsByMetadata.putIfAbsent(key, () => <SongModel>[]).add(song);
    }
  }

  final Map<String, AlbumModel> _albumsById;
  final Map<String, SongModel> _songsById;
  final Map<String, AlbumModel> _albumsByMetadata = <String, AlbumModel>{};
  final Map<String, AlbumModel> _uniqueAlbumsByTitle = <String, AlbumModel>{};
  final Set<String> _ambiguousAlbumTitles = <String>{};
  final Map<String, List<SongModel>> _songsByMetadata =
      <String, List<SongModel>>{};

  StatsArtworkIdentity forSong(SongStats stat) {
    final librarySong = _songsById[stat.songId];
    if (librarySong != null) return _librarySongIdentity(librarySong);

    final recordedAlbumId = stat.albumId?.trim();
    if (recordedAlbumId != null &&
        recordedAlbumId.isNotEmpty &&
        _albumsById.containsKey(recordedAlbumId)) {
      return _albumIdentity(recordedAlbumId);
    }

    final metadataSong = _songForMetadata(stat.songTitle, stat.songArtist);
    if (metadataSong != null) return _librarySongIdentity(metadataSong);

    if (recordedAlbumId != null && recordedAlbumId.isNotEmpty) {
      return _albumIdentity(recordedAlbumId);
    }
    return _songIdentity(stat.songId);
  }

  StatsArtworkIdentity forArtist(ArtistStats stat) {
    final recordedAlbumId = stat.randomAlbumId?.trim();
    if (recordedAlbumId != null &&
        recordedAlbumId.isNotEmpty &&
        _albumsById.containsKey(recordedAlbumId)) {
      return _albumIdentity(recordedAlbumId);
    }

    final randomSongId = stat.randomSongId?.trim();
    if (randomSongId != null && randomSongId.isNotEmpty) {
      final librarySong = _songsById[randomSongId];
      if (librarySong != null) return _librarySongIdentity(librarySong);
    }

    final artistKey = _normalize(stat.artistName);
    for (final song in _songsById.values) {
      final album = _albumForId(song.albumId);
      final searchableArtist = '${song.artist}\n${album?.artist ?? ''}';
      if (!_normalize(searchableArtist).contains(artistKey)) continue;
      final albumId = song.albumId?.trim();
      if (albumId != null && albumId.isNotEmpty) {
        return _albumIdentity(albumId);
      }
      return _songIdentity(song.id);
    }

    if (recordedAlbumId != null && recordedAlbumId.isNotEmpty) {
      return _albumIdentity(recordedAlbumId);
    }
    if (randomSongId != null && randomSongId.isNotEmpty) {
      return _songIdentity(randomSongId);
    }
    return StatsArtworkIdentity(
      cacheId: 'stats_artist_${_safeSyntheticKey(stat.artistName)}',
      artworkUrl: null,
    );
  }

  StatsArtworkIdentity forAlbum(AlbumStats stat) {
    final recordedAlbumId = stat.albumId.trim();
    if (recordedAlbumId.isNotEmpty &&
        _albumsById.containsKey(recordedAlbumId)) {
      return _albumIdentity(recordedAlbumId);
    }

    final title = stat.albumName?.trim();
    final artist = stat.albumArtist?.trim();
    if (title != null && title.isNotEmpty) {
      AlbumModel? album;
      if (artist != null && artist.isNotEmpty) {
        album = _albumsByMetadata[_albumMetadataKey(title, artist)];
      }
      album ??= _uniqueAlbumsByTitle[_normalize(title)];
      if (album != null) return _albumIdentity(album.id);
    }

    if (recordedAlbumId.isNotEmpty) {
      return _albumIdentity(recordedAlbumId);
    }
    return StatsArtworkIdentity(
      cacheId: 'stats_album_${_safeSyntheticKey('$title|$artist')}',
      artworkUrl: null,
    );
  }

  AlbumModel? _albumForId(String? albumId) {
    final normalizedId = albumId?.trim();
    if (normalizedId == null || normalizedId.isEmpty) return null;
    return _albumsById[normalizedId];
  }

  SongModel? _songForMetadata(String? title, String? artist) {
    final normalizedTitle = title?.trim();
    final normalizedArtist = artist?.trim();
    if (normalizedTitle == null ||
        normalizedTitle.isEmpty ||
        normalizedArtist == null ||
        normalizedArtist.isEmpty) {
      return null;
    }

    final candidates =
        _songsByMetadata[_songMetadataKey(normalizedTitle, normalizedArtist)];
    if (candidates == null || candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    // Duplicate library entries are safe to use only when they all resolve to
    // the same artwork identity. Otherwise choosing one could show the wrong
    // cover for a genuinely ambiguous title + artist pair.
    final identities = candidates
        .map((song) => song.albumId?.trim().isNotEmpty == true
            ? song.albumId!.trim()
            : 'song_${song.id}')
        .toSet();
    return identities.length == 1 ? candidates.first : null;
  }

  StatsArtworkIdentity _librarySongIdentity(SongModel song) {
    final albumId = song.albumId?.trim();
    if (albumId != null && albumId.isNotEmpty) {
      return _albumIdentity(albumId);
    }
    return _songIdentity(song.id);
  }

  StatsArtworkIdentity _albumIdentity(String albumId) {
    final album = _albumsById[albumId];
    return StatsArtworkIdentity(
      cacheId: albumId,
      artworkUrl: resolveAlbumArtworkUrl(
        albumId: albumId,
        coverArt: album?.coverArt,
      ),
    );
  }

  StatsArtworkIdentity _songIdentity(String songId) {
    final normalizedId = songId.trim();
    return StatsArtworkIdentity(
      cacheId: 'song_$normalizedId',
      artworkUrl: normalizedId.isEmpty
          ? null
          : '/api/song-artwork/${Uri.encodeComponent(normalizedId)}',
    );
  }

  static String _albumMetadataKey(String title, String artist) =>
      '${_normalize(title)}|${_normalize(artist)}';

  static String _songMetadataKey(String title, String artist) =>
      '${_normalize(title)}|||${_normalize(artist)}';

  static String _normalize(String value) => value
      .replaceAll(RegExp('[\u0000-\u001f\u007f-\u009f\u200b-\u200f\ufeff]'), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[\u2010-\u2015\u2212]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _safeSyntheticKey(String value) {
    final normalized = _normalize(value);
    return Uri.encodeComponent(normalized.isEmpty ? 'unknown' : normalized);
  }
}
