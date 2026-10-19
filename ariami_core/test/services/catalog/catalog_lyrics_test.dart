import 'package:ariami_core/services/catalog/catalog_migrations.dart';
import 'package:ariami_core/services/catalog/catalog_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('Catalog database migrations & lyrics column', () {
    test('version 8 migration adds has_lyrics column to existing database', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);

      // Run up to version 7
      db.userVersion = 7;
      db.execute('''
CREATE TABLE songs (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  genre TEXT NULL,
  album_id TEXT NULL,
  duration_seconds INTEGER NOT NULL,
  track_number INTEGER NULL,
  file_size_bytes INTEGER NULL,
  modified_epoch_ms INTEGER NULL,
  bitrate_kbps INTEGER NULL,
  artwork_key TEXT NULL,
  updated_token INTEGER NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0
);
''');

      CatalogMigrations.migrate(db);

      expect(db.userVersion, 8);
      final columns = db
          .select('PRAGMA table_info(songs);')
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns.contains('has_lyrics'), isTrue);
    });

    test('CatalogRepository upserts and reads hasLyrics correctly', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);

      CatalogMigrations.migrate(db);
      final repo = CatalogRepository(database: db);

      final songWithLyrics = CatalogSongRecord(
        id: 'song-with-lyrics',
        filePath: '/music/song1.mp3',
        title: 'Song 1',
        artist: 'Artist 1',
        durationSeconds: 200,
        updatedToken: 1,
        hasLyrics: true,
      );

      final songWithoutLyrics = CatalogSongRecord(
        id: 'song-without-lyrics',
        filePath: '/music/song2.mp3',
        title: 'Song 2',
        artist: 'Artist 2',
        durationSeconds: 180,
        updatedToken: 2,
        hasLyrics: false,
      );

      repo.upsertSong(songWithLyrics);
      repo.upsertSong(songWithoutLyrics);

      final fetched1 = repo.getSongById('song-with-lyrics');
      expect(fetched1, isNotNull);
      expect(fetched1!.hasLyrics, isTrue);

      final fetched2 = repo.getSongById('song-without-lyrics');
      expect(fetched2, isNotNull);
      expect(fetched2!.hasLyrics, isFalse);

      final page = repo.listSongsPage();
      expect(page.items.length, 2);
      final map = {for (final item in page.items) item.id: item.hasLyrics};
      expect(map['song-with-lyrics'], isTrue);
      expect(map['song-without-lyrics'], isFalse);
    });
  });
}
