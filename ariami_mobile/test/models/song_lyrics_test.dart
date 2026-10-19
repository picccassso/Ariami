import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/models/song.dart';
import 'package:ariami_mobile/utils/song_from_model.dart';

void main() {
  group('Song lyrics support', () {
    test('default hasLyrics is false', () {
      final song = Song(
        id: 's1',
        title: 'Title',
        artist: 'Artist',
        duration: const Duration(seconds: 180),
        filePath: 's1.mp3',
        fileSize: 1000,
        modifiedTime: DateTime.now(),
      );
      expect(song.hasLyrics, isFalse);
    });

    test('toJson and fromJson preserves hasLyrics', () {
      final song = Song(
        id: 's2',
        title: 'Title',
        artist: 'Artist',
        duration: const Duration(seconds: 200),
        filePath: 's2.mp3',
        fileSize: 2000,
        modifiedTime: DateTime.utc(2026, 1, 1),
        hasLyrics: true,
      );

      final json = song.toJson();
      expect(json['hasLyrics'], isTrue);

      final decoded = Song.fromJson(json);
      expect(decoded.hasLyrics, isTrue);
    });

    test('copyWith updates hasLyrics', () {
      final song = Song(
        id: 's3',
        title: 'Title',
        artist: 'Artist',
        duration: const Duration(seconds: 120),
        filePath: 's3.mp3',
        fileSize: 1000,
        modifiedTime: DateTime.now(),
        hasLyrics: false,
      );

      final updated = song.copyWith(hasLyrics: true);
      expect(updated.hasLyrics, isTrue);
    });

    test('songFromModel maps hasLyrics from SongModel', () {
      final modelWithLyrics = SongModel(
        id: 's4',
        title: 'Title',
        artist: 'Artist',
        duration: 150,
        hasLyrics: true,
      );

      final song = songFromModel(modelWithLyrics);
      expect(song.hasLyrics, isTrue);

      final modelWithoutLyrics = SongModel(
        id: 's5',
        title: 'Title',
        artist: 'Artist',
        duration: 150,
        hasLyrics: false,
      );

      final songWithout = songFromModel(modelWithoutLyrics);
      expect(songWithout.hasLyrics, isFalse);
    });
  });
}
