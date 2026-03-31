import 'package:ariami_mobile/utils/artwork_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAlbumArtworkUrl', () {
    test('returns explicit coverArt when provided', () {
      final resolved = resolveAlbumArtworkUrl(
        albumId: 'album-1',
        coverArt: '/api/artwork/custom',
      );

      expect(resolved, '/api/artwork/custom');
    });

    test('falls back to album endpoint when coverArt is missing', () {
      final resolved = resolveAlbumArtworkUrl(
        albumId: 'album-1',
      );

      expect(resolved, '/api/artwork/album-1');
    });

    test('encodes albumId in fallback endpoint', () {
      final resolved = resolveAlbumArtworkUrl(
        albumId: 'my album/id',
      );

      expect(resolved, '/api/artwork/my%20album%2Fid');
    });

    test('returns null when albumId is blank and coverArt missing', () {
      final resolved = resolveAlbumArtworkUrl(
        albumId: '   ',
      );

      expect(resolved, isNull);
    });
  });
}
