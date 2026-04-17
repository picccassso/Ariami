import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/models/cache_entry.dart';
import 'package:ariami_mobile/services/cache/cache_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
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
}
