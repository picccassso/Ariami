import 'dart:io';

import 'package:ariami_mobile/database/library_sync_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_support/private_sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    await initPrivateSqfliteFfi('sync_db_upgrade_test_');
  });

  test('an upgrade resets the sync state so new fields are refetched',
      () async {
    final directory = await databaseFactory.getDatabasesPath();
    await Directory(directory).create(recursive: true);
    final path = p.join(directory, 'library_sync.db');

    // An install last written by the previous schema: from the old client's
    // point of view it is perfectly up to date, so only a version bump can
    // make it refetch the catalog.
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sync_state (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              last_applied_token INTEGER NOT NULL DEFAULT 0,
              bootstrap_complete INTEGER NOT NULL DEFAULT 0,
              last_sync_epoch_ms INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.insert('sync_state', <String, Object?>{
            'id': 1,
            'last_applied_token': 42,
            'bootstrap_complete': 1,
            'last_sync_epoch_ms': 1234,
          });
        },
      ),
    );
    await legacy.close();

    final database = await LibrarySyncDatabase.create();
    final state = await database.getSyncState();

    expect(state.bootstrapComplete, isFalse);
    expect(state.lastAppliedToken, 0);
    await database.close();
  });
}
