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
