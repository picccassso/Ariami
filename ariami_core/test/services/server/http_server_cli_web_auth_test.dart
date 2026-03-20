import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CLI web auth compatibility', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late Directory webDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_cli_web_auth_');
      webDir = Directory(p.join(testDir.path, 'web'))
        ..createSync(recursive: true);
      File(p.join(webDir.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><body>cli web</body></html>',
      );
      File(p.join(webDir.path, 'main.dart.js')).writeAsStringSync('// js');

      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      server.setWebAssetsPath(webDir.path);
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('without flag, auth middleware still blocks root path', () async {
      server.setFeatureFlags(
        const AriamiFeatureFlags(enableApiScopedAuthForCliWeb: false),
      );
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'cli-web-user',
          'password': 'cli-web-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final rootResponse =
          await _sendRawRequest(url: Uri.parse('http://127.0.0.1:$port/'));
      expect(rootResponse.statusCode, 401);

      final decoded = jsonDecode(rootResponse.body) as Map<String, dynamic>;
      expect(
        (decoded['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.authRequired,
      );
    });

    test('with flag, root is static while protected APIs still require auth',
        () async {
      server.setFeatureFlags(
        const AriamiFeatureFlags(enableApiScopedAuthForCliWeb: true),
      );
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'cli-web-user-2',
          'password': 'cli-web-pass-2',
        },
      );
      expect(registerResponse.statusCode, 200);

      final rootResponse =
          await _sendRawRequest(url: Uri.parse('http://127.0.0.1:$port/'));
      expect(rootResponse.statusCode, 200);
      expect(rootResponse.body, contains('cli web'));

      final unauthorizedStats = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/stats'),
      );
      expect(unauthorizedStats.statusCode, 401);
      expect(
        (unauthorizedStats.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.authRequired,
      );

      final loginResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'cli-web-user-2',
          'password': 'cli-web-pass-2',
          'deviceId': 'cli-web-device',
          'deviceName': 'CLI Web Device',
        },
      );
      expect(loginResponse.statusCode, 200);
      final token = loginResponse.jsonBody['sessionToken'] as String?;
      expect(token, isNotNull);

      final authorizedStats = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/stats'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      expect(authorizedStats.statusCode, 200);
      expect(authorizedStats.jsonBody['songCount'], isA<int>());
    });
  });

  group('Admin dashboard auth APIs', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late Directory webDir;

    setUp(() async {
      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();

      testDir = await Directory.systemTemp.createTemp('ariami_admin_api_');
      webDir = Directory(p.join(testDir.path, 'web'))
        ..createSync(recursive: true);
      File(p.join(webDir.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><body>admin api</body></html>',
      );
      File(p.join(webDir.path, 'main.dart.js')).writeAsStringSync('// js');

      server.libraryManager
          .setCachePath(p.join(testDir.path, 'metadata_cache.json'));
      server.setWebAssetsPath(webDir.path);
      await server.initializeAuth(
        usersFilePath: p.join(testDir.path, 'users.json'),
        sessionsFilePath: p.join(testDir.path, 'sessions.json'),
        forceReinitialize: true,
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test(
        'ping-only traffic does not register connected client rows, authenticated connect does',
        () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
        },
      );
      expect(registerAdmin.statusCode, 200);

      final loginAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
          'deviceId': 'admin-device',
          'deviceName': 'Admin Device',
        },
      );
      expect(loginAdmin.statusCode, 200);
      final adminToken = loginAdmin.jsonBody['sessionToken'] as String;

      final pingOnlyResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse(
          'http://127.0.0.1:$port/api/ping?deviceId=ping-only-device&deviceName=Ping%20Only',
        ),
      );
      expect(pingOnlyResponse.statusCode, 200);

      final registerTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
        },
      );
      expect(registerTarget.statusCode, 200);

      final loginTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
          'deviceId': 'target-connect-device',
          'deviceName': 'Target Connect Device',
        },
      );
      expect(loginTarget.statusCode, 200);
      final targetToken = loginTarget.jsonBody['sessionToken'] as String;

      final connectTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
        jsonBody: <String, dynamic>{
          'deviceId': 'target-connect-device',
          'deviceName': 'Target Connect Device',
          'appVersion': '3.2.0',
          'platform': 'test',
        },
      );
      expect(connectTarget.statusCode, 200);

      final clientsResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/connected-clients'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
      );
      expect(clientsResponse.statusCode, 200);

      final clients =
          (clientsResponse.jsonBody['clients'] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, dynamic>>();

      expect(
        clients.where((c) => c['deviceId'] == 'ping-only-device'),
        isEmpty,
      );

      final targetRows =
          clients.where((c) => c['deviceId'] == 'target-connect-device');
      expect(targetRows.length, equals(1));
    });

    test('admin connected-clients returns username/device rows', () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
        },
      );
      expect(registerAdmin.statusCode, 200);

      final loginAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
          'deviceId': 'admin-device',
          'deviceName': 'Admin Device',
        },
      );
      expect(loginAdmin.statusCode, 200);
      final adminToken = loginAdmin.jsonBody['sessionToken'] as String;
      final adminUserId = loginAdmin.jsonBody['userId'] as String;

      final connectAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
        jsonBody: <String, dynamic>{
          'deviceId': 'admin-device',
          'deviceName': 'Admin Device',
          'appVersion': '3.2.0',
          'platform': 'test',
        },
      );
      expect(connectAdmin.statusCode, 200);

      final response = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/connected-clients'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
      );
      expect(response.statusCode, 200);

      final clients =
          (response.jsonBody['clients'] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, dynamic>>();
      final row = clients.firstWhere((c) => c['deviceId'] == 'admin-device');

      expect(row['deviceName'], equals('Admin Device'));
      expect(row['clientType'], equals('user_device'));
      expect(row['userId'], equals(adminUserId));
      expect(row['username'], equals('admin-user'));
      expect(
          () => DateTime.parse(row['connectedAt'] as String), returnsNormally);
      expect(() => DateTime.parse(row['lastHeartbeat'] as String),
          returnsNormally);
    });

    test('admin kick-client disconnects target and revokes sessions', () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
        },
      );
      expect(registerAdmin.statusCode, 200);

      final loginAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
          'deviceId': 'admin-device',
          'deviceName': 'Admin Device',
        },
      );
      expect(loginAdmin.statusCode, 200);
      final adminToken = loginAdmin.jsonBody['sessionToken'] as String;

      final registerTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
        },
      );
      expect(registerTarget.statusCode, 200);

      final loginTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
        },
      );
      expect(loginTarget.statusCode, 200);
      final targetToken = loginTarget.jsonBody['sessionToken'] as String;

      final connectTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
        jsonBody: <String, dynamic>{
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
          'appVersion': '3.2.0',
          'platform': 'test',
        },
      );
      expect(connectTarget.statusCode, 200);

      final kickResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/kick-client'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
        jsonBody: <String, dynamic>{'deviceId': 'target-device'},
      );
      expect(kickResponse.statusCode, 200);
      expect(kickResponse.jsonBody['status'], equals('kicked'));
      expect(kickResponse.jsonBody['deviceId'], equals('target-device'));
      expect(kickResponse.jsonBody['revokedSessionCount'],
          greaterThanOrEqualTo(1));

      final targetMe = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/me'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
      );
      expect(targetMe.statusCode, 401);
      expect(
        (targetMe.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.sessionExpired,
      );

      final clientsAfterKick = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/connected-clients'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
      );
      expect(clientsAfterKick.statusCode, 200);
      final clients = (clientsAfterKick.jsonBody['clients'] as List<dynamic>? ??
              <dynamic>[])
          .cast<Map<String, dynamic>>();
      expect(clients.where((c) => c['deviceId'] == 'target-device'), isEmpty);
    });

    test('admin change-password updates password and revokes sessions',
        () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
        },
      );
      expect(registerAdmin.statusCode, 200);

      final loginAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
          'deviceId': 'admin-device',
          'deviceName': 'Admin Device',
        },
      );
      expect(loginAdmin.statusCode, 200);
      final adminToken = loginAdmin.jsonBody['sessionToken'] as String;

      final registerTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'old-target-pass',
        },
      );
      expect(registerTarget.statusCode, 200);

      final loginTargetOld = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'old-target-pass',
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
        },
      );
      expect(loginTargetOld.statusCode, 200);
      final oldTargetToken = loginTargetOld.jsonBody['sessionToken'] as String;

      final changePassword = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/change-password'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'newPassword': 'new-target-pass',
        },
      );
      expect(changePassword.statusCode, 200);
      expect(changePassword.jsonBody['status'], equals('password_changed'));
      expect(changePassword.jsonBody['username'], equals('target-user'));
      expect(changePassword.jsonBody['revokedSessionCount'],
          greaterThanOrEqualTo(1));

      final targetMeWithOldToken = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/me'),
        headers: <String, String>{'Authorization': 'Bearer $oldTargetToken'},
      );
      expect(targetMeWithOldToken.statusCode, 401);
      expect(
        (targetMeWithOldToken.jsonBody['error']
            as Map<String, dynamic>)['code'],
        AuthErrorCodes.sessionExpired,
      );

      final oldPasswordLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'old-target-pass',
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
        },
      );
      expect(oldPasswordLogin.statusCode, 401);
      expect(
        (oldPasswordLogin.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.invalidCredentials,
      );

      final newPasswordLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'new-target-pass',
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
        },
      );
      expect(newPasswordLogin.statusCode, 200);
      expect(newPasswordLogin.jsonBody['sessionToken'], isA<String>());
    });

    test('non-admin is blocked from admin endpoints', () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      final registerAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
        },
      );
      expect(registerAdmin.statusCode, 200);

      final registerNonAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'regular-user',
          'password': 'regular-pass',
        },
      );
      expect(registerNonAdmin.statusCode, 200);

      final loginNonAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'regular-user',
          'password': 'regular-pass',
          'deviceId': 'regular-device',
          'deviceName': 'Regular Device',
        },
      );
      expect(loginNonAdmin.statusCode, 200);
      final nonAdminToken = loginNonAdmin.jsonBody['sessionToken'] as String;

      final connectedClients = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/connected-clients'),
        headers: <String, String>{'Authorization': 'Bearer $nonAdminToken'},
      );
      expect(connectedClients.statusCode, 403);
      expect(
        (connectedClients.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.forbiddenAdmin,
      );

      final kickClient = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/kick-client'),
        headers: <String, String>{'Authorization': 'Bearer $nonAdminToken'},
        jsonBody: <String, dynamic>{'deviceId': 'some-device'},
      );
      expect(kickClient.statusCode, 403);
      expect(
        (kickClient.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.forbiddenAdmin,
      );

      final changePassword = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/change-password'),
        headers: <String, String>{'Authorization': 'Bearer $nonAdminToken'},
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'newPassword': 'new-admin-pass',
        },
      );
      expect(changePassword.statusCode, 403);
      expect(
        (changePassword.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.forbiddenAdmin,
      );
    });

    test('disconnect preserves session token - can reconnect without re-login',
        () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      // Register and login
      final registerResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'offline-user',
          'password': 'offline-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final loginResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'offline-user',
          'password': 'offline-pass',
          'deviceId': 'offline-device',
          'deviceName': 'Offline Device',
        },
      );
      expect(loginResponse.statusCode, 200);
      final token = loginResponse.jsonBody['sessionToken'] as String;

      // Connect
      final connectResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
        jsonBody: <String, dynamic>{
          'deviceId': 'offline-device',
          'deviceName': 'Offline Device',
          'appVersion': '3.2.0',
          'platform': 'test',
        },
      );
      expect(connectResponse.statusCode, 200);

      // Disconnect (simulates going offline)
      final disconnectResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/disconnect'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
        jsonBody: <String, dynamic>{},
      );
      expect(disconnectResponse.statusCode, 200);

      // Session should still be valid after disconnect
      final meResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/me'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      expect(meResponse.statusCode, 200);
      expect(meResponse.jsonBody['username'], equals('offline-user'));

      // Should be able to reconnect with same token
      final reconnectResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
        jsonBody: <String, dynamic>{
          'deviceId': 'offline-device',
          'deviceName': 'Offline Device',
          'appVersion': '3.2.0',
          'platform': 'test',
        },
      );
      expect(reconnectResponse.statusCode, 200);
    });

    test('admin kick still revokes session after disconnect change', () async {
      final port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );

      // Register admin
      final registerAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
        },
      );
      expect(registerAdmin.statusCode, 200);

      final loginAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
          'password': 'admin-pass',
          'deviceId': 'admin-device',
          'deviceName': 'Admin Device',
        },
      );
      expect(loginAdmin.statusCode, 200);
      final adminToken = loginAdmin.jsonBody['sessionToken'] as String;

      // Register and login target user
      final registerTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/register'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
        },
      );
      expect(registerTarget.statusCode, 200);

      final loginTarget = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
        },
      );
      expect(loginTarget.statusCode, 200);
      final targetToken = loginTarget.jsonBody['sessionToken'] as String;

      // Target connects then disconnects (simulates offline toggle)
      await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
        jsonBody: <String, dynamic>{
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
          'appVersion': '3.2.0',
          'platform': 'test',
        },
      );
      await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/disconnect'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
        jsonBody: <String, dynamic>{},
      );

      // Token should still be valid after disconnect
      final meAfterDisconnect = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/me'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
      );
      expect(meAfterDisconnect.statusCode, 200);

      // Admin kick revokes the session
      final kickResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/kick-client'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
        jsonBody: <String, dynamic>{'deviceId': 'target-device'},
      );
      expect(kickResponse.statusCode, 200);

      // Token should now be invalid after admin kick
      final meAfterKick = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/me'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
      );
      expect(meAfterKick.statusCode, 401);
      expect(
        (meAfterKick.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.sessionExpired,
      );
    });
  });
}

class _RawResponse {
  const _RawResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class _JsonResponse {
  const _JsonResponse({
    required this.statusCode,
    required this.jsonBody,
  });

  final int statusCode;
  final Map<String, dynamic> jsonBody;
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind('127.0.0.1', 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_RawResponse> _sendRawRequest({
  required Uri url,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    headers?.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return _RawResponse(statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

Future<_JsonResponse> _sendJsonRequest({
  required String method,
  required Uri url,
  Map<String, String>? headers,
  Map<String, dynamic>? jsonBody,
}) async {
  final client = HttpClient();
  try {
    final request =
        method == 'POST' ? await client.postUrl(url) : await client.getUrl(url);

    final mergedHeaders = <String, String>{
      if (headers != null) ...headers,
      if (jsonBody != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    mergedHeaders.forEach(request.headers.set);

    if (jsonBody != null) {
      request.write(jsonEncode(jsonBody));
    }

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final decodedBody = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;

    return _JsonResponse(
        statusCode: response.statusCode, jsonBody: decodedBody);
  } finally {
    client.close(force: true);
  }
}
