import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/services/api/connection_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const sqfliteChannel = MethodChannel('com.tekartik.sqflite');
  final secureStorage = <String, String>{};
  final dbVersions = <int, int>{};
  var nextDbId = 1;

  setUpAll(() {
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sqfliteChannel, (call) async {
      final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
      final id = args['id'] as int?;
      final sql = (args['sql'] as String? ?? '').trim();

      switch (call.method) {
        case 'getDatabasesPath':
          return '/tmp';
        case 'openDatabase':
          final openedId = nextDbId++;
          dbVersions[openedId] = 0;
          return <String, Object?>{'id': openedId};
        case 'closeDatabase':
          if (id != null) {
            dbVersions.remove(id);
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
            dbVersions[id] = int.parse(setVersion.group(1)!);
          }
          return null;
        case 'query':
          if (sql.toUpperCase().startsWith('PRAGMA USER_VERSION')) {
            return <Map<String, Object?>>[
              <String, Object?>{'user_version': dbVersions[id] ?? 0},
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
      final key = args['key'] as String?;

      switch (call.method) {
        case 'read':
          if (key == null) return null;
          return secureStorage[key];
        case 'write':
          if (key != null) {
            secureStorage[key] = (args['value'] as String?) ?? '';
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStorage.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStorage.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStorage);
        case 'containsKey':
          if (key == null) return false;
          return secureStorage.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sqfliteChannel, null);
  });

  setUp(() async {
    secureStorage.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ConnectionService().logout();
  });

  test('logout clears secure auth data and in-memory auth state', () async {
    secureStorage['session_token'] = 'test-session-token';
    secureStorage['user_id'] = 'user-123';
    secureStorage['username'] = 'test-user';

    final connectionService = ConnectionService();
    await connectionService.loadAuthInfo();

    expect(connectionService.sessionToken, equals('test-session-token'));
    expect(connectionService.userId, equals('user-123'));
    expect(connectionService.username, equals('test-user'));
    expect(connectionService.isAuthenticated, isTrue);

    await connectionService.logout();

    expect(connectionService.sessionToken, isNull);
    expect(connectionService.userId, isNull);
    expect(connectionService.username, isNull);
    expect(connectionService.isAuthenticated, isFalse);
    expect(connectionService.isConnected, isFalse);
    expect(secureStorage.containsKey('session_token'), isFalse);
    expect(secureStorage.containsKey('user_id'), isFalse);
    expect(secureStorage.containsKey('username'), isFalse);
  });

  test('handleSessionExpired emits once and clears auth without recursion',
      () async {
    secureStorage['session_token'] = 'expired-session-token';
    secureStorage['user_id'] = 'user-123';
    secureStorage['username'] = 'test-user';

    final connectionService = ConnectionService();
    await connectionService.loadAuthInfo();

    var sessionExpiredEvents = 0;
    final sessionSub = connectionService.sessionExpiredStream.listen((_) {
      sessionExpiredEvents++;
    });
    addTearDown(sessionSub.cancel);

    await connectionService.handleSessionExpired();
    await Future<void>.delayed(Duration.zero);

    expect(connectionService.isAuthenticated, isFalse);
    expect(connectionService.sessionToken, isNull);
    expect(connectionService.userId, isNull);
    expect(connectionService.username, isNull);
    expect(connectionService.isConnected, isFalse);
    expect(sessionExpiredEvents, equals(1));
    expect(secureStorage.containsKey('session_token'), isFalse);
    expect(secureStorage.containsKey('user_id'), isFalse);
    expect(secureStorage.containsKey('username'), isFalse);
  });

  test('resolveServerUrl expands relative media paths using stored server info',
      () async {
    await _saveServerInfoForRestore(port: 8080);

    final connectionService = ConnectionService();
    await connectionService.loadServerInfoFromStorage();

    expect(
      connectionService.resolveServerUrl('/api/artwork/album-123'),
      equals('http://127.0.0.1:8080/api/artwork/album-123'),
    );
    expect(
      connectionService.resolveServerUrl(
        '/api/artwork/album-123?size=thumbnail',
      ),
      equals('http://127.0.0.1:8080/api/artwork/album-123?size=thumbnail'),
    );
    expect(
      connectionService.resolveServerUrl(
        'http://cdn.example.com/api/artwork/album-123',
      ),
      equals('http://cdn.example.com/api/artwork/album-123'),
    );
  });

  test(
      'tryRestoreConnection handles AUTH_REQUIRED as auth failure when token is missing',
      () async {
    final mockServer = await _startReconnectFailureServer(
      connectErrorCode: ApiErrorCodes.authRequired,
      connectErrorMessage: 'Authentication required',
    );
    addTearDown(() async {
      await mockServer.close(force: true);
    });
    await _saveServerInfoForRestore(port: mockServer.port);

    final connectionService = ConnectionService();
    await connectionService.loadAuthInfo();

    var sessionExpiredEvents = 0;
    final sessionSub = connectionService.sessionExpiredStream.listen((_) {
      sessionExpiredEvents++;
    });
    addTearDown(sessionSub.cancel);

    final restored = await HttpOverrides.runZoned(
      () => connectionService.tryRestoreConnection(),
      createHttpClient: (context) =>
          _PassthroughHttpOverrides().createHttpClient(context),
    );
    await Future<void>.delayed(Duration.zero);

    expect(restored, isFalse);
    expect(connectionService.didLastRestoreFailForAuth, isTrue);
    expect(
      connectionService.lastRestoreFailureCode,
      equals(ApiErrorCodes.authRequired),
    );
    expect(
      connectionService.lastRestoreFailureMessage,
      equals('Authentication required'),
    );
    expect(connectionService.isConnected, isFalse);
    expect(connectionService.isAuthenticated, isFalse);
    expect(connectionService.sessionToken, isNull);
    expect(sessionExpiredEvents, greaterThanOrEqualTo(1));
  });

  test(
      'tryRestoreConnection handles SESSION_EXPIRED by clearing auth and reporting auth failure',
      () async {
    final mockServer = await _startReconnectFailureServer(
      connectErrorCode: ApiErrorCodes.sessionExpired,
      connectErrorMessage: 'Session expired',
    );
    addTearDown(() async {
      await mockServer.close(force: true);
    });
    await _saveServerInfoForRestore(port: mockServer.port);

    secureStorage['session_token'] = 'expired-token';
    secureStorage['user_id'] = 'user-restore';
    secureStorage['username'] = 'restore-user';

    final connectionService = ConnectionService();
    await connectionService.loadAuthInfo();
    expect(connectionService.isAuthenticated, isTrue);

    var sessionExpiredEvents = 0;
    final sessionSub = connectionService.sessionExpiredStream.listen((_) {
      sessionExpiredEvents++;
    });
    addTearDown(sessionSub.cancel);

    final restored = await HttpOverrides.runZoned(
      () => connectionService.tryRestoreConnection(),
      createHttpClient: (context) =>
          _PassthroughHttpOverrides().createHttpClient(context),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(restored, isFalse);
    expect(connectionService.didLastRestoreFailForAuth, isTrue);
    expect(
      connectionService.lastRestoreFailureCode,
      equals(ApiErrorCodes.sessionExpired),
    );
    expect(
      connectionService.lastRestoreFailureMessage,
      equals('Session expired'),
    );
    expect(connectionService.isConnected, isFalse);
    expect(connectionService.isAuthenticated, isFalse);
    expect(connectionService.sessionToken, isNull);
    expect(secureStorage.containsKey('session_token'), isFalse);
    expect(secureStorage.containsKey('user_id'), isFalse);
    expect(secureStorage.containsKey('username'), isFalse);
    expect(sessionExpiredEvents, greaterThanOrEqualTo(1));
  });

  test('tryRestoreConnection with server error does not set auth failure flag',
      () async {
    final mockServer = await _startReconnectFailureServer(
      connectErrorCode: ApiErrorCodes.serverError,
      connectErrorMessage: 'Internal server error',
    );
    addTearDown(() async {
      await mockServer.close(force: true);
    });
    await _saveServerInfoForRestore(port: mockServer.port);

    secureStorage['session_token'] = 'valid-token';
    secureStorage['user_id'] = 'user-server-err';
    secureStorage['username'] = 'server-err-user';

    final connectionService = ConnectionService();
    await connectionService.loadAuthInfo();
    expect(connectionService.isAuthenticated, isTrue);

    final restored = await HttpOverrides.runZoned(
      () => connectionService.tryRestoreConnection(),
      createHttpClient: (context) =>
          _PassthroughHttpOverrides().createHttpClient(context),
    );

    expect(restored, isFalse);
    expect(connectionService.didLastRestoreFailForAuth, isFalse);
    expect(
      connectionService.lastRestoreFailureCode,
      equals(ApiErrorCodes.serverError),
    );
    // Auth state should be preserved for non-auth failures
    expect(connectionService.isAuthenticated, isTrue);
    expect(connectionService.sessionToken, equals('valid-token'));
  });
}

Future<HttpServer> _startReconnectFailureServer({
  required String connectErrorCode,
  required String connectErrorMessage,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  unawaited(
    server.forEach((request) async {
      await utf8.decoder.bind(request).join();

      if (request.uri.path == '/api/ping' && request.method == 'GET') {
        await _writeJson(
          request.response,
          <String, dynamic>{'status': 'ok'},
        );
        return;
      }

      if (request.uri.path == '/api/connect' && request.method == 'POST') {
        request.response.statusCode = HttpStatus.unauthorized;
        await _writeJson(
          request.response,
          <String, dynamic>{
            'error': <String, dynamic>{
              'code': connectErrorCode,
              'message': connectErrorMessage,
            },
          },
        );
        return;
      }

      if (request.uri.path == '/api/auth/logout' && request.method == 'POST') {
        await _writeJson(
          request.response,
          <String, dynamic>{'success': true},
        );
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await _writeJson(
        request.response,
        <String, dynamic>{
          'error': <String, dynamic>{
            'code': 'NOT_FOUND',
            'message': 'Route not found in test server',
          },
        },
      );
    }),
  );

  return server;
}

Future<void> _saveServerInfoForRestore({
  required int port,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'server_info',
    jsonEncode(
      <String, dynamic>{
        'server': '127.0.0.1',
        'port': port,
        'name': 'Test Server',
        'version': 'test',
        'authRequired': true,
        'legacyMode': false,
      },
    ),
  );
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, dynamic> body,
) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

class _PassthroughHttpOverrides extends HttpOverrides {}
