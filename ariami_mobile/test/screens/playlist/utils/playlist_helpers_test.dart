import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/playlist/utils/playlist_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDuration', () {
    test('should format 0 seconds as 0:00', () {
      expect(formatDuration(0), '0:00');
    });

    test('should format 30 seconds as 0:30', () {
      expect(formatDuration(30), '0:30');
    });

    test('should format 60 seconds as 1:00', () {
      expect(formatDuration(60), '1:00');
    });

    test('should format 90 seconds as 1:30', () {
      expect(formatDuration(90), '1:30');
    });

    test('should format 180 seconds as 3:00', () {
      expect(formatDuration(180), '3:00');
    });
  });

  group('songModelToSong', () {
    test('should convert SongModel to Song with basic fields', () {
      final songModel = SongModel(
        id: 'song-1',
        title: 'Test Song',
        artist: 'Test Artist',
        duration: 180,
      );

      final albumInfoMap = <String, ({String name, String artist})>{};
      final song = songModelToSong(songModel, albumInfoMap);

      expect(song.id, 'song-1');
      expect(song.title, 'Test Song');
      expect(song.artist, 'Test Artist');
      expect(song.duration, const Duration(seconds: 180));
    });

    test('should look up album info when albumId is present', () {
      final songModel = SongModel(
        id: 'song-1',
        title: 'Test Song',
        artist: 'Test Artist',
        albumId: 'album-1',
        duration: 180,
      );

      final albumInfoMap = <String, ({String name, String artist})>{
        'album-1': (name: 'Test Album', artist: 'Album Artist'),
      };

      final song = songModelToSong(songModel, albumInfoMap);

      expect(song.album, 'Test Album');
      expect(song.albumArtist, 'Album Artist');
    });

    test('should handle missing album info gracefully', () {
      final songModel = SongModel(
        id: 'song-1',
        title: 'Test Song',
        artist: 'Test Artist',
        albumId: 'album-1',
        duration: 180,
      );

      final albumInfoMap = <String, ({String name, String artist})>{};

      final song = songModelToSong(songModel, albumInfoMap);

      expect(song.album, isNull);
      expect(song.albumArtist, isNull);
    });
  });
}
