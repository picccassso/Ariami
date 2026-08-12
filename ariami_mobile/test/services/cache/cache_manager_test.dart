import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/models/cache_entry.dart';
import 'package:ariami_mobile/services/cache/cache_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory docsDir;
  late CacheManager cacheManager;

  Future<void> seedLegacyEntries(List<CacheEntry> entries) async {
    final artworkDir = Directory(p.join(docsDir.path, 'cache', 'artwork'));
    final songsDir = Directory(p.join(docsDir.path, 'cache', 'songs'));
    await artworkDir.create(recursive: true);
    await songsDir.create(recursive: true);

    for (final entry in entries) {
      final file = File(entry.path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(entry.size, 3));
    }

    SharedPreferences.setMockInitialValues(<String, Object>{
      'cache_entries':
          entries.map((entry) => jsonEncode(entry.toJson())).toList(),
      'cache_limit_mb': 1,
    });
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    docsDir = await Directory.systemTemp.createTemp('ariami_cache_test_');

    // Keep this file's databases out of the shared FFI default directory so
    // concurrent test files can't lock or delete each other's databases.
    await databaseFactory.setDatabasesPath(p.join(docsDir.path, 'databases'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
        case 'getApplicationSupportDirectory':
        case 'getLibraryDirectory':
        case 'getExternalStorageDirectory':
          return docsDir.path;
        case 'getExternalCacheDirectories':
        case 'getExternalStorageDirectories':
          return <String>[docsDir.path];
        default:
          return docsDir.path;
      }
    });
  });

  setUp(() async {
    cacheManager = CacheManager();
    await cacheManager.resetForTests();

    final dbRoot = await getDatabasesPath();
    await deleteDatabase(p.join(dbRoot, 'cache_metadata.db'));

    final cacheDir = Directory(p.join(docsDir.path, 'cache'));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }

    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  tearDown(() async {
    await cacheManager.resetForTests();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
    }
  });

  group('CacheManager song limit enforcement', () {
    test('evicts older songs to keep song cache within hard limit', () async {
      final now = DateTime.now().subtract(const Duration(hours: 2));
      final oldSong = CacheEntry(
        id: 'song-old',
        type: CacheType.song,
        path: p.join(docsDir.path, 'cache', 'songs', 'song-old.mp3'),
        size: 700 * 1024,
        lastAccessed: now,
      );
      final newSong = CacheEntry(
        id: 'song-new',
        type: CacheType.song,
        path: p.join(docsDir.path, 'cache', 'songs', 'song-new.mp3'),
        size: 700 * 1024,
        lastAccessed: now.add(const Duration(minutes: 5)),
      );

      await seedLegacyEntries(<CacheEntry>[oldSong, newSong]);

      await cacheManager.initialize();
      await cacheManager.setCacheLimit(1);

      final limitBytes = cacheManager.getCacheLimit() * 1024 * 1024;
      expect(
          await cacheManager.getSongCacheSize(), lessThanOrEqualTo(limitBytes));
      expect(await cacheManager.getSongCacheCount(), 1);
      expect(await cacheManager.isSongCached('song-old'), isFalse);
      expect(await cacheManager.isSongCached('song-new'), isTrue);
    });

    test('artwork cache does not consume song limit budget', () async {
      final now = DateTime.now().subtract(const Duration(hours: 2));
      final artwork = CacheEntry(
        id: 'artwork-1',
        type: CacheType.artwork,
        path: p.join(docsDir.path, 'cache', 'artwork', 'artwork-1.jpg'),
        size: 900 * 1024,
        lastAccessed: now,
      );
      final song = CacheEntry(
        id: 'song-1',
        type: CacheType.song,
        path: p.join(docsDir.path, 'cache', 'songs', 'song-1.mp3'),
        size: 700 * 1024,
        lastAccessed: now.add(const Duration(minutes: 5)),
      );

      await seedLegacyEntries(<CacheEntry>[artwork, song]);

      await cacheManager.initialize();
      await cacheManager.setCacheLimit(1);

      final limitBytes = cacheManager.getCacheLimit() * 1024 * 1024;
      expect(
          await cacheManager.getSongCacheSize(), lessThanOrEqualTo(limitBytes));
      expect(await cacheManager.isSongCached('song-1'), isTrue);
      expect(await cacheManager.getArtworkCacheCount(), 1);
      expect(await cacheManager.getTotalCacheSize(), greaterThan(limitBytes));
    });
  });

  group('CacheManager artwork revalidation', () {
    test('upgrades version-one cache metadata without losing artwork',
        () async {
      final dbPath = p.join(await getDatabasesPath(), 'cache_metadata.db');
      final artworkPath = p.join(
        docsDir.path,
        'cache',
        'artwork',
        'legacy-cover.jpg',
      );
      final artworkFile = File(artworkPath);
      await artworkFile.parent.create(recursive: true);
      await artworkFile.writeAsBytes(<int>[7, 8, 9]);
      final legacyDb = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE cache_entries (
              id TEXT NOT NULL,
              type TEXT NOT NULL,
              path TEXT NOT NULL,
              size INTEGER NOT NULL,
              last_accessed TEXT NOT NULL,
              created_at TEXT NOT NULL,
              PRIMARY KEY (id, type)
            )
          ''');
        },
      );
      final now = DateTime.now().toIso8601String();
      await legacyDb.insert('cache_entries', <String, Object>{
        'id': 'legacy-cover',
        'type': CacheType.artwork.toString(),
        'path': artworkPath,
        'size': 3,
        'last_accessed': now,
        'created_at': now,
      });
      await legacyDb.close();

      await cacheManager.initialize();
      expect(await cacheManager.getArtworkPath('legacy-cover'), artworkPath);
      expect(
        await cacheManager.cacheArtworkFromBytes(
          'post-upgrade-cover',
          <int>[1, 2, 3],
        ),
        isNotNull,
      );
    });

    test('uses ETags and refreshes changed or legacy cached artwork', () async {
      await cacheManager.initialize();
      final adapter = _ArtworkAdapter(
        bytes: <int>[1, 2, 3],
        etag: '"art-v1"',
      );
      cacheManager.setHttpClientAdapterForTests(adapter);
      const baseUrl = 'https://ariami.test/artwork';

      final path = await cacheManager.cacheArtwork('album-1', baseUrl);
      expect(path, isNotNull);
      expect(await File(path!).readAsBytes(), <int>[1, 2, 3]);

      final unchanged =
          await cacheManager.revalidateCachedArtwork('album-1', baseUrl);
      expect(unchanged.changed, isFalse);
      expect(adapter.receivedValidators.last, '"art-v1"');

      adapter
        ..bytes = <int>[4, 5, 6]
        ..etag = '"art-v2"';
      final changed = await cacheManager.revalidateCachedArtwork(
        'album-1',
        '$baseUrl?catalog=2',
      );
      expect(changed.changed, isTrue);
      expect(changed.path, path);
      expect(adapter.receivedValidators.last, '"art-v1"');
      expect(await File(path).readAsBytes(), <int>[4, 5, 6]);

      final requestsBeforeRepeat = adapter.requestCount;
      final repeated = await cacheManager.revalidateCachedArtwork(
        'album-1',
        '$baseUrl?catalog=2',
      );
      expect(repeated.changed, isFalse);
      expect(adapter.requestCount, requestsBeforeRepeat);

      final legacyPath = await cacheManager.cacheArtworkFromBytes(
        'song_legacy_thumb',
        <int>[7, 8, 9],
      );
      final legacyRefresh = await cacheManager.revalidateCachedArtwork(
        'song_legacy_thumb',
        '$baseUrl?legacy=1',
      );
      expect(legacyRefresh.changed, isTrue);
      expect(adapter.receivedValidators.last, isNull);
      expect(await File(legacyPath!).readAsBytes(), <int>[4, 5, 6]);
    });
  });
}

class _ArtworkAdapter implements HttpClientAdapter {
  _ArtworkAdapter({required this.bytes, required this.etag});

  List<int> bytes;
  String etag;
  int requestCount = 0;
  final List<String?> receivedValidators = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    String? validator;
    for (final header in options.headers.entries) {
      if (header.key.toLowerCase() == 'if-none-match') {
        validator = header.value as String?;
      }
    }
    receivedValidators.add(validator);
    return ResponseBody.fromBytes(
      validator == etag ? const <int>[] : bytes,
      validator == etag ? HttpStatus.notModified : HttpStatus.ok,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['image/jpeg'],
        'etag': <String>[etag],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
