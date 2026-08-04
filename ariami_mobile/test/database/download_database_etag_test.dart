import 'dart:io';

import 'package:ariami_mobile/database/download_database.dart';
import 'package:ariami_mobile/models/download_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The v2 schema, verbatim, so the upgrade path is exercised against what is
/// actually on disk for installs that predate the resume validator.
const String _v2CreateTable = '''
  CREATE TABLE download_tasks (
    id TEXT PRIMARY KEY,
    song_id TEXT NOT NULL,
    server_id TEXT,
    user_id TEXT,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_id TEXT,
    album_name TEXT,
    album_artist TEXT,
    album_art TEXT NOT NULL,
    download_url TEXT NOT NULL,
    download_quality TEXT NOT NULL,
    download_original INTEGER NOT NULL DEFAULT 0,
    duration INTEGER NOT NULL DEFAULT 0,
    track_number INTEGER,
    status TEXT NOT NULL DEFAULT 'DownloadStatus.pending',
    progress REAL NOT NULL DEFAULT 0.0,
    bytes_downloaded INTEGER NOT NULL DEFAULT 0,
    total_bytes INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    native_backend TEXT,
    native_task_id TEXT
  )
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('ariami_dl_db_test_');
    await databaseFactory.setDatabasesPath(p.join(tempDir.path, 'databases'));
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  DownloadTask buildTask({String? etag}) {
    return DownloadTask(
      id: 'song_track-1',
      songId: 'track-1',
      serverId: 'http://127.0.0.1:8080/api',
      userId: 'alex',
      title: 'Track One',
      artist: 'Artist',
      albumArt: '',
      downloadUrl: 'http://127.0.0.1:8080/api/download/track-1',
      totalBytes: 1024,
      status: DownloadStatus.paused,
      bytesDownloaded: 256,
      downloadEtag: etag,
    );
  }

  test('the resume validator survives a save and reload', () async {
    final database = await DownloadDatabase.create();
    await database.upsertTask(buildTask(etag: '"dl-1024-99"'));

    final reloaded = await DownloadDatabase.create();
    final tasks = await reloaded.loadDownloadQueue();

    expect(tasks, hasLength(1));
    expect(tasks.single.downloadEtag, '"dl-1024-99"',
        reason: 'without this the resume can never send If-Range');
  });

  test('a task with no validator round-trips as null', () async {
    final database = await DownloadDatabase.create();
    await database.upsertTask(buildTask());

    final tasks = await (await DownloadDatabase.create()).loadDownloadQueue();
    expect(tasks.single.downloadEtag, isNull);
  });

  test('an existing v2 install upgrades without losing its queue', () async {
    // A broken migration here would not degrade downloads — it would throw on
    // open and take the whole feature out for every upgrading user.
    final dbPath = p.join(await databaseFactory.getDatabasesPath(),
        'downloads.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    final legacy = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async => db.execute(_v2CreateTable),
      ),
    );
    await legacy.insert('download_tasks', <String, Object?>{
      'id': 'song_legacy-1',
      'song_id': 'legacy-1',
      'title': 'Legacy Track',
      'artist': 'Artist',
      'album_art': '',
      'download_url': 'http://127.0.0.1:8080/api/download/legacy-1',
      'download_quality': 'high',
      'status': 'DownloadStatus.paused',
      'progress': 0.25,
      'bytes_downloaded': 256,
      'total_bytes': 1024,
    });
    await legacy.close();

    final upgraded = await DownloadDatabase.create();
    final tasks = await upgraded.loadDownloadQueue();

    expect(tasks, hasLength(1));
    expect(tasks.single.songId, 'legacy-1');
    expect(tasks.single.bytesDownloaded, 256,
        reason: 'the pre-existing partial must still be resumable');
    expect(tasks.single.downloadEtag, isNull,
        reason: 'rows written before the column exists have no validator');

    // And the new column is writable on the upgraded schema.
    await upgraded.upsertTask(buildTask(etag: '"dl-1024-7"'));
    final after = await upgraded.loadDownloadQueue();
    expect(
      after.firstWhere((t) => t.songId == 'track-1').downloadEtag,
      '"dl-1024-7"',
    );
  });
}
