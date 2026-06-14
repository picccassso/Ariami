import 'dart:io';

import 'package:ariami_core/services/catalog/catalog_database.dart';
import 'package:ariami_core/services/catalog/catalog_migrations.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  group('CatalogDatabase', () {
    late Directory tempDir;
    late String databasePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ariami_catalog_db_');
      databasePath = '${tempDir.path}/catalog.db';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initialize creates schema + indexes and sets current user version',
        () {
      final database = CatalogDatabase(databasePath: databasePath);
      database.initialize();
      addTearDown(database.close);

      final db = database.database;
      expect(db.userVersion, equals(CatalogMigrations.currentVersion));

      final tables = db
          .select(
            '''
SELECT name
FROM sqlite_master
WHERE type = 'table'
ORDER BY name ASC;
''',
          )
          .map((row) => row['name'] as String)
          .toSet();

      expect(
        tables,
        containsAll(<String>{
          'albums',
          'songs',
          'playlists',
          'playlist_songs',
          'artwork_variants',
          'library_changes',
          'download_jobs',
          'download_job_items',
        }),
      );

      final indexes = db
          .select(
            '''
SELECT name
FROM sqlite_master
WHERE type = 'index'
ORDER BY name ASC;
''',
          )
          .map((row) => row['name'] as String)
          .toSet();

      expect(
        indexes,
        containsAll(<String>{
          'idx_songs_album_deleted_updated',
          'idx_albums_deleted_updated',
          'idx_library_changes_token',
          'idx_download_jobs_user_status',
        }),
      );
    });

    test('initialize is idempotent and does not reset existing data', () {
      final database = CatalogDatabase(databasePath: databasePath);
      database.initialize();

      database.database.execute(
        '''
INSERT INTO albums (
  id, title, artist, year, cover_art_key, song_count, duration_seconds,
  updated_token, is_deleted
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
''',
        <Object?>[
          'album-1',
          'Album 1',
          'Artist 1',
          2026,
          null,
          1,
          180,
          1,
          0,
        ],
      );

      // Second initialize should no-op.
      database.initialize();

      final row = database.database.select(
        'SELECT id, title FROM albums WHERE id = ?;',
        <Object?>['album-1'],
      );
      expect(row.length, equals(1));
      expect(row.first['title'], equals('Album 1'));

      database.close();
    });

    test('initialize applies microSD-friendly runtime pragmas', () {
      final database = CatalogDatabase(databasePath: databasePath);
      database.initialize();
      addTearDown(database.close);

      final db = database.database;
      expect(db.select('PRAGMA journal_mode;').first['journal_mode'], 'wal');
      expect(db.select('PRAGMA synchronous;').first['synchronous'], 1);
      expect(db.select('PRAGMA temp_store;').first['temp_store'], 2);
      expect(db.select('PRAGMA busy_timeout;').first['timeout'], 5000);
      expect(db.select('PRAGMA cache_size;').first['cache_size'], -8192);
    });

    test('migration scrubs invisible characters from existing text rows', () {
      // Build a v4 database directly and seed it with NUL-tainted values,
      // mimicking rows written by older scans before sanitization existed.
      final rawDb = sqlite.sqlite3.open(databasePath);
      CatalogMigrations.migrate(rawDb);
      // Force the version back to 4 so the v5 scrub runs on reopen.
      rawDb.userVersion = 4;
      rawDb.execute(
        '''
INSERT INTO albums (
  id, title, artist, year, cover_art_key, song_count, duration_seconds,
  updated_token, is_deleted
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
''',
        <Object?>['al-1', 'These Things Happen\u0000', 'G-Eazy\u0000', 2014,
            null, 1, 180, 1, 0],
      );
      rawDb.execute(
        '''
INSERT INTO songs (
  id, file_path, title, artist, album_id, duration_seconds, track_number,
  file_size_bytes, modified_epoch_ms, bitrate_kbps, artwork_key,
  updated_token, is_deleted
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
''',
        <Object?>['s-1', '/m/a.mp3', 'Opportunity Cost\u0000', 'G-Eazy\u0000',
            'al-1', 180, 5, 1000, 1, 320, null, 1, 0],
      );
      // A clean standalone single, as the remix arrived.
      rawDb.execute(
        '''
INSERT INTO songs (
  id, file_path, title, artist, album_id, duration_seconds, track_number,
  file_size_bytes, modified_epoch_ms, bitrate_kbps, artwork_key,
  updated_token, is_deleted
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
''',
        <Object?>['s-2', '/m/b.mp3', 'Last Night (Remix)', 'G-Eazy', null, 200,
            null, 1000, 1, 320, null, 2, 0],
      );
      rawDb.dispose();

      // Reopen through CatalogDatabase, which runs migrations up to current.
      final database = CatalogDatabase(databasePath: databasePath);
      database.initialize();
      addTearDown(database.close);
      final db = database.database;

      expect(db.userVersion, equals(CatalogMigrations.currentVersion));

      // Assert on the raw stored bytes via BLOB, not a plain text read: SQLite
      // truncates a TEXT value at its first NUL, so a text read would look clean
      // even if the NUL were still in the database.
      final album = db
          .select(
            'SELECT artist, instr(CAST(artist AS BLOB), X\'00\') AS nul, '
            'length(CAST(artist AS BLOB)) AS blen FROM albums;',
          )
          .first;
      expect(album['artist'], equals('G-Eazy'));
      expect(album['nul'], equals(0), reason: 'no NUL byte should remain');
      expect(album['blen'], equals(6), reason: 'clean "G-Eazy" is 6 bytes');

      // Every song artist is now NUL-free, so the album track and the standalone
      // single share an identical value and no longer fragment into two groups.
      final songs = db.select(
        'SELECT artist, instr(CAST(artist AS BLOB), X\'00\') AS nul '
        'FROM songs ORDER BY id;',
      );
      for (final row in songs) {
        expect(row['nul'], equals(0), reason: 'no NUL byte should remain');
      }
      final artists = songs.map((r) => r['artist'] as String).toSet();
      expect(artists, equals(<String>{'G-Eazy'}));
    });

    test('initialize fails for forward-incompatible schema versions', () {
      final rawDb = sqlite.sqlite3.open(databasePath);
      rawDb.userVersion = CatalogMigrations.currentVersion + 1;
      rawDb.dispose();

      final database = CatalogDatabase(databasePath: databasePath);

      expect(
        database.initialize,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('newer than supported'),
          ),
        ),
      );
      expect(database.isInitialized, isFalse);
    });
  });
}
