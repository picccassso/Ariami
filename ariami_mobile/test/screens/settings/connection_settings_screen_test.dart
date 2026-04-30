import 'dart:convert';

import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/settings/connection_settings_screen.dart';
import 'package:ariami_mobile/services/api/connection_service.dart';
import 'package:ariami_mobile/services/offline/offline_playback_service.dart';
import 'package:flutter/material.dart';
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
    await OfflinePlaybackService().setManualOfflineMode(false);
    await OfflinePlaybackService().notifyConnectionRestored();
  });

  testWidgets('connection settings renders username from auth state',
      (tester) async {
    secureStorage['session_token'] = 'session-token';
    secureStorage['user_id'] = 'user-42';
    secureStorage['username'] = 'alice';
    await ConnectionService().loadAuthInfo();

    await tester.pumpWidget(
      const MaterialApp(
        home: ConnectionSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('User ID'), findsOneWidget);
    expect(find.text('user-42'), findsOneWidget);
  });

  testWidgets('logout clears auth data and navigates to welcome route',
      (tester) async {
    secureStorage['session_token'] = 'session-token';
    secureStorage['user_id'] = 'user-99';
    secureStorage['username'] = 'logout-user';
    await ConnectionService().loadAuthInfo();

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/connection',
        routes: <String, WidgetBuilder>{
          '/': (_) =>
              const Scaffold(body: Center(child: Text('WELCOME_SCREEN'))),
          '/connection': (_) => const ConnectionSettingsScreen(),
          '/auth/login': (_) =>
              const Scaffold(body: Center(child: Text('LOGIN_SCREEN'))),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Log Out'), findsOneWidget);
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'LOG OUT'));
    await tester.pumpAndSettle();

    expect(find.text('WELCOME_SCREEN'), findsOneWidget);

    final connectionService = ConnectionService();
    expect(connectionService.sessionToken, isNull);
    expect(connectionService.userId, isNull);
    expect(connectionService.username, isNull);
    expect(connectionService.isAuthenticated, isFalse);
    expect(secureStorage.containsKey('session_token'), isFalse);
    expect(secureStorage.containsKey('user_id'), isFalse);
    expect(secureStorage.containsKey('username'), isFalse);
  });

  testWidgets(
      'retry connection shows auth-required message when reconnect fails with AUTH_REQUIRED',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionSettingsScreen(
          retryConnectionAttempt: () async => const RetryConnectionResult(
            restored: false,
            didAuthFail: true,
            failureCode: ApiErrorCodes.authRequired,
            failureMessage: 'Authentication required',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('RETRY CONNECTION'));
    await tester.tap(find.text('RETRY CONNECTION'));
    await tester.pump();

    expect(
      find.text('Authentication required. Please log in to reconnect.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'retry connection shows session-expired message when reconnect fails with SESSION_EXPIRED',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionSettingsScreen(
          retryConnectionAttempt: () async => const RetryConnectionResult(
            restored: false,
            didAuthFail: true,
            failureCode: ApiErrorCodes.sessionExpired,
            failureMessage: 'Session expired',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('RETRY CONNECTION'));
    await tester.tap(find.text('RETRY CONNECTION'));
    await tester.pump();

    expect(
      find.text('Session expired. Please log in again.'),
      findsOneWidget,
    );
  });

  testWidgets('connection settings shows active LAN and Tailscale route info',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_info': jsonEncode(<String, Object?>{
        'server': '192.168.68.64',
        'lanServer': '192.168.68.64',
        'tailscaleServer': '100.101.102.103',
        'port': 8080,
        'name': 'Alexs-MacBook-Pro.local',
        'version': '4.3.0',
        'authRequired': false,
        'legacyMode': false,
        'downloadLimits': <String, int>{
          'maxConcurrent': 4,
          'maxQueue': 10000,
          'maxConcurrentPerUser': 2,
          'maxQueuePerUser': 10000,
        },
      }),
    });

    await ConnectionService().loadServerInfoFromStorage();

    await tester.pumpWidget(
      const MaterialApp(
        home: ConnectionSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Local Network'), findsOneWidget);
    expect(find.text('Active Address'), findsOneWidget);
    expect(find.text('192.168.68.64'), findsWidgets);
    expect(find.text('LAN Address'), findsOneWidget);
    expect(find.text('Tailscale Address'), findsOneWidget);
    expect(find.text('100.101.102.103'), findsOneWidget);
  });
}
