import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

const MethodChannel _sqfliteChannel = MethodChannel('com.tekartik.sqflite');
final Map<int, int> _dbVersions = <int, int>{};
int _nextDbId = 1;

void installSqfliteTestMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_sqfliteChannel, (call) async {
    final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
    final id = args['id'] as int?;
    final sql = (args['sql'] as String? ?? '').trim();

    switch (call.method) {
      case 'getDatabasesPath':
        return '/tmp';
      case 'openDatabase':
        final openedId = _nextDbId++;
        _dbVersions[openedId] = 0;
        return <String, Object?>{'id': openedId};
      case 'closeDatabase':
        if (id != null) {
          _dbVersions.remove(id);
        }
        return null;
      case 'deleteDatabase':
        return null;
      case 'databaseExists':
        return false;
      case 'execute':
        final setVersion = RegExp(
          r'^PRAGMA\s+user_version\s*=\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(sql);
        if (id != null && setVersion != null) {
          _dbVersions[id] = int.parse(setVersion.group(1)!);
        }
        return null;
      case 'query':
        if (sql.toUpperCase().startsWith('PRAGMA USER_VERSION')) {
          return <Map<String, Object?>>[
            <String, Object?>{'user_version': _dbVersions[id] ?? 0},
          ];
        }
        return <Map<String, Object?>>[];
      case 'insert':
        return 1;
      case 'update':
      case 'delete':
        return 1;
      case 'batch':
        final operations =
            (args['operations'] as List<dynamic>? ?? const <dynamic>[]);
        return List<dynamic>.filled(operations.length, null);
      case 'options':
      case 'debug':
        return null;
      default:
        return null;
    }
  });
}

void uninstallSqfliteTestMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_sqfliteChannel, null);
  _dbVersions.clear();
  _nextDbId = 1;
}
