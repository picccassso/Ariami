import 'package:flutter_test/flutter_test.dart';
import 'package:ariami_mobile/database/library_sync_database.dart';
import '../test_support/private_sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    await initPrivateSqfliteFfi('sync_db_lyrics_test_');
  });

  group('LibrarySyncDatabase lyrics support', () {
    test('persists and reads hasLyrics correctly', () async {
      final db = await LibrarySyncDatabase.create();

      const song1 = LibrarySongRow(
        id: 's_lyrics_1',
        title: 'Song With Lyrics',
        artist: 'Artist',
        duration: 120,
        hasLyrics: true,
      );

      const song2 = LibrarySongRow(
        id: 's_lyrics_2',
        title: 'Song Without Lyrics',
        artist: 'Artist',
        duration: 180,
        hasLyrics: false,
      );

      await db.upsertSongs([song1, song2]);

      final read1 = await db.getSongById('s_lyrics_1');
      expect(read1, isNotNull);
      expect(read1!.hasLyrics, isTrue);

      final read2 = await db.getSongById('s_lyrics_2');
      expect(read2, isNotNull);
      expect(read2!.hasLyrics, isFalse);

      final allSongs = await db.listSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      expect(songMap['s_lyrics_1']?.hasLyrics, isTrue);
      expect(songMap['s_lyrics_2']?.hasLyrics, isFalse);
    });

    test('bootstrap staging songs persists hasLyrics and copies to main songs',
        () async {
      final db = await LibrarySyncDatabase.create();

      const stagingSong = LibrarySongRow(
        id: 's_staging_1',
        title: 'Staging Song',
        artist: 'Artist',
        duration: 210,
        hasLyrics: true,
      );

      await db.upsertBootstrapStagingSongs([stagingSong]);
      await db.replacePrimaryWithBootstrapStaging();

      final song = await db.getSongById('s_staging_1');
      expect(song, isNotNull);
      expect(song!.hasLyrics, isTrue);
    });
  });
}
