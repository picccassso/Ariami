import 'package:ariami_core/services/playlists/created_playlist_id.dart';
import 'package:test/test.dart';

void main() {
  group('created playlist id', () {
    test('recognizes the current prefix', () {
      expect(isCreatedPlaylistId('created:123-abc'), isTrue);
    });

    test('recognizes the legacy desktop prefix for back-compat', () {
      expect(isCreatedPlaylistId('desktop-created:123-abc'), isTrue);
    });

    test('rejects server folder playlist ids', () {
      expect(isCreatedPlaylistId('pl_a1b2c3d4e5f6'), isFalse);
      expect(isCreatedPlaylistId(''), isFalse);
      expect(isCreatedPlaylistId('__LIKED_SONGS__'), isFalse);
    });

    test('recognizes Liked Songs as account-owned but not user-created', () {
      expect(isAccountOwnedPlaylistId(likedSongsPlaylistId), isTrue);
      expect(isCreatedPlaylistId(likedSongsPlaylistId), isFalse);
    });

    test('newCreatedPlaylistId is recognized and carries the current prefix',
        () {
      final id = newCreatedPlaylistId();
      expect(id.startsWith(createdPlaylistPrefix), isTrue);
      expect(isCreatedPlaylistId(id), isTrue);
    });

    test('newCreatedPlaylistId yields unique ids', () {
      final ids = <String>{
        for (var i = 0; i < 1000; i++) newCreatedPlaylistId()
      };
      expect(ids.length, 1000);
    });
  });
}
