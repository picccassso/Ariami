import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes the sqflite FFI factory and points it at a freshly created
/// temp directory private to this test file.
///
/// `flutter test` runs test files concurrently, and the FFI factory's default
/// databases directory (`.dart_tool/sqflite_common_ffi/databases/`) is shared
/// across all of them. Test files that open — or delete — the same database
/// name there intermittently fail with "database is locked" (SQLite error 5).
/// Call this from `setUpAll` before any code touches a database.
///
/// Returns the temp directory in case the caller also wants to root other
/// fake storage (documents dir, caches) under it.
Future<Directory> initPrivateSqfliteFfi(String tempDirPrefix) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await Directory.systemTemp.createTemp(tempDirPrefix);
  await databaseFactory.setDatabasesPath(p.join(dir.path, 'databases'));
  return dir;
}
