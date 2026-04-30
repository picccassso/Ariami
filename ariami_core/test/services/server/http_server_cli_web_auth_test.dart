import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/auth_models.dart';
import 'package:ariami_core/models/feature_flags.dart';
import 'package:ariami_core/models/quality_preset.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:ariami_core/services/transcoding/transcoding_service.dart';
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
          'appVersion': '4.3.0',
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
          'appVersion': '4.3.0',
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

    test('dashboard login stays active while the same user logs in on mobile',
        () async {
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
          'username': 'shared-user',
          'password': 'shared-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final dashboardLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'shared-user',
          'password': 'shared-pass',
          'deviceId': 'cli-web-dashboard',
          'deviceName': 'Ariami CLI Web Dashboard',
        },
      );
      expect(dashboardLogin.statusCode, 200);
      final dashboardToken = dashboardLogin.jsonBody['sessionToken'] as String;

      final mobileLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'shared-user',
          'password': 'shared-pass',
          'deviceId': 'mobile-device',
          'deviceName': 'Alex iPhone',
        },
      );
      expect(mobileLogin.statusCode, 200);
      final mobileToken = mobileLogin.jsonBody['sessionToken'] as String;

      final dashboardStats = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/stats'),
        headers: <String, String>{
          'Authorization': 'Bearer $dashboardToken',
        },
      );
      expect(dashboardStats.statusCode, 200);

      final dashboardConnect = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{
          'Authorization': 'Bearer $dashboardToken',
        },
        jsonBody: <String, dynamic>{
          'deviceId': 'cli-web-dashboard',
          'deviceName': 'Ariami CLI Web Dashboard',
          'appVersion': '4.3.0',
          'platform': 'web',
        },
      );
      expect(dashboardConnect.statusCode, 200);

      final mobileConnect = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{
          'Authorization': 'Bearer $mobileToken',
        },
        jsonBody: <String, dynamic>{
          'deviceId': 'mobile-device',
          'deviceName': 'Alex iPhone',
          'appVersion': '4.3.0',
          'platform': 'ios',
        },
      );
      expect(mobileConnect.statusCode, 200);

      final connectedClients = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/connected-clients'),
        headers: <String, String>{
          'Authorization': 'Bearer $dashboardToken',
        },
      );
      expect(connectedClients.statusCode, 200);

      final rows = (connectedClients.jsonBody['clients'] as List<dynamic>? ??
              <dynamic>[])
          .cast<Map<String, dynamic>>();
      expect(rows.any((row) => row['deviceId'] == 'cli-web-dashboard'), isTrue);
      expect(rows.any((row) => row['deviceId'] == 'mobile-device'), isTrue);
    });

    test(
        'stats mobileClients excludes dashboard presence; counts real devices',
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
          'username': 'stats-dash-user',
          'password': 'stats-dash-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final dashLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'stats-dash-user',
          'password': 'stats-dash-pass',
          'deviceId': 'cli-web-dashboard-stats',
          'deviceName': 'Ariami CLI Web Dashboard',
        },
      );
      expect(dashLogin.statusCode, 200);
      final dashToken = dashLogin.jsonBody['sessionToken'] as String;

      Future<Map<String, dynamic>> fetchStats() async {
        final r = await _sendJsonRequest(
          method: 'GET',
          url: Uri.parse('http://127.0.0.1:$port/api/stats'),
          headers: <String, String>{
            'Authorization': 'Bearer $dashToken',
          },
        );
        expect(r.statusCode, 200);
        return r.jsonBody;
      }

      var s = await fetchStats();
      expect(s['mobileClients'], 0);
      expect(s['connectedClients'], 1);

      final dashConnect = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $dashToken'},
        jsonBody: <String, dynamic>{
          'deviceId': 'cli-web-dashboard-stats',
          'deviceName': 'Ariami CLI Web Dashboard',
          'appVersion': '4.3.0',
          'platform': 'web',
        },
      );
      expect(dashConnect.statusCode, 200);

      s = await fetchStats();
      expect(s['mobileClients'], 0);
      expect(s['connectedClients'], 1);

      final mobLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'stats-dash-user',
          'password': 'stats-dash-pass',
          'deviceId': 'phone-stats',
          'deviceName': 'Stats Test Phone',
        },
      );
      expect(mobLogin.statusCode, 200);
      final mobToken = mobLogin.jsonBody['sessionToken'] as String;

      s = await fetchStats();
      expect(s['mobileClients'], 1);
      expect(s['connectedClients'], 2);

      final mobConnect = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/connect'),
        headers: <String, String>{'Authorization': 'Bearer $mobToken'},
        jsonBody: <String, dynamic>{
          'deviceId': 'phone-stats',
          'deviceName': 'Stats Test Phone',
          'appVersion': '4.3.0',
          'platform': 'ios',
        },
      );
      expect(mobConnect.statusCode, 200);

      s = await fetchStats();
      expect(s['mobileClients'], 1);
      expect(s['connectedClients'], 2);
    });

    test('admin user-activity returns empty users when no activity', () async {
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

      final activityResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/user-activity'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
      );
      expect(activityResponse.statusCode, 200);

      final users =
          (activityResponse.jsonBody['users'] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, dynamic>>();
      expect(users, isEmpty);
      expect(
        () =>
            DateTime.parse(activityResponse.jsonBody['generatedAt'] as String),
        returnsNormally,
      );
    });

    test(
        'admin user-activity reports active/queued downloads and in-flight transcodes',
        () async {
      final musicDir = await Directory(p.join(testDir.path, 'music_activity'))
          .create(recursive: true);
      await _writeAudioStub(p.join(musicDir.path, 'Artist - Activity.mp3'));
      await server.libraryManager.scanMusicFolder(musicDir.path);
      final repository = server.libraryManager.createCatalogRepository();
      expect(repository, isNotNull);
      final songPage = repository!.listSongsPage(limit: 1);
      expect(songPage.items, isNotEmpty);
      final songId = songPage.items.first.id;

      server.setDownloadLimits(
        maxConcurrent: 1,
        maxQueue: 4,
        maxConcurrentPerUser: 1,
        maxQueuePerUser: 4,
      );
      server.setTranscodingService(
        _SlowDownloadTranscodingService(
          delay: const Duration(milliseconds: 900),
        ),
      );

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
      final targetUserId = loginTarget.jsonBody['userId'] as String;

      final ticketResponse = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/stream-ticket'),
        headers: <String, String>{'Authorization': 'Bearer $targetToken'},
        jsonBody: <String, dynamic>{
          'songId': songId,
          'quality': 'medium',
        },
      );
      expect(ticketResponse.statusCode, 200);
      final streamToken = ticketResponse.jsonBody['streamToken'] as String;

      final downloadUri = Uri.parse(
        'http://127.0.0.1:$port/api/download/$songId'
        '?quality=medium&streamToken=$streamToken',
      );

      final client = HttpClient();
      final firstResponseFuture = () async {
        final request = await client.getUrl(downloadUri);
        return request.close();
      }();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      final secondResponseFuture = () async {
        final request = await client.getUrl(downloadUri);
        return request.close();
      }();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      final activityResponse = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/user-activity'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
      );
      expect(activityResponse.statusCode, 200);

      final users =
          (activityResponse.jsonBody['users'] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, dynamic>>();
      final targetRow =
          users.firstWhere((user) => user['userId'] == targetUserId);

      expect(targetRow['username'], equals('target-user'));
      expect(targetRow['isDownloading'], isTrue);
      expect(targetRow['activeDownloads'], equals(1));
      expect(targetRow['queuedDownloads'], greaterThanOrEqualTo(1));
      expect(targetRow['isTranscoding'], isTrue);
      expect(targetRow['inFlightDownloadTranscodes'], greaterThanOrEqualTo(1));

      final firstResponse = await firstResponseFuture;
      await firstResponse.drain<void>();
      final secondResponse = await secondResponseFuture;
      await secondResponse.drain<void>();
      client.close(force: true);
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
          'appVersion': '4.3.0',
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

    test('admin delete-user removes account and revokes active sessions',
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
          'password': 'target-pass',
        },
      );
      expect(registerTarget.statusCode, 200);
      final targetUserId = registerTarget.jsonBody['userId'] as String;

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
          'appVersion': '4.3.0',
          'platform': 'test',
        },
      );
      expect(connectTarget.statusCode, 200);

      final deleteUser = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/delete-user'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
        jsonBody: <String, dynamic>{'userId': targetUserId},
      );
      expect(deleteUser.statusCode, 200);
      expect(deleteUser.jsonBody['status'], equals('user_deleted'));
      expect(deleteUser.jsonBody['userId'], equals(targetUserId));
      expect(deleteUser.jsonBody['username'], equals('target-user'));
      expect(
          deleteUser.jsonBody['revokedSessionCount'], greaterThanOrEqualTo(1));

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

      final deletedUserLogin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/auth/login'),
        jsonBody: <String, dynamic>{
          'username': 'target-user',
          'password': 'target-pass',
          'deviceId': 'target-device',
          'deviceName': 'Target Device',
        },
      );
      expect(deletedUserLogin.statusCode, 401);
      expect(
        (deletedUserLogin.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.invalidCredentials,
      );
    });

    test('cannot delete the last remaining admin account', () async {
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
      final adminUserId = registerAdmin.jsonBody['userId'] as String;

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

      final deleteAdmin = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/delete-user'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
        jsonBody: <String, dynamic>{'userId': adminUserId},
      );
      expect(deleteAdmin.statusCode, 409);
      expect(
        (deleteAdmin.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.lastAdminProtected,
      );

      final meAfterRejectedDelete = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/me'),
        headers: <String, String>{'Authorization': 'Bearer $adminToken'},
      );
      expect(meAfterRejectedDelete.statusCode, 200);
      expect(meAfterRejectedDelete.jsonBody['username'], equals('admin-user'));
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

      final userActivity = await _sendJsonRequest(
        method: 'GET',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/user-activity'),
        headers: <String, String>{'Authorization': 'Bearer $nonAdminToken'},
      );
      expect(userActivity.statusCode, 403);
      expect(
        (userActivity.jsonBody['error'] as Map<String, dynamic>)['code'],
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

      final deleteUser = await _sendJsonRequest(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:$port/api/admin/delete-user'),
        headers: <String, String>{'Authorization': 'Bearer $nonAdminToken'},
        jsonBody: <String, dynamic>{
          'username': 'admin-user',
        },
      );
      expect(deleteUser.statusCode, 403);
      expect(
        (deleteUser.jsonBody['error'] as Map<String, dynamic>)['code'],
        AuthErrorCodes.forbiddenAdmin,
      );
    });

    test('websocket identify without session token closes with auth-required',
        () async {
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
          'username': 'ws-auth-user',
          'password': 'ws-auth-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/api/ws');
      final subscription = ws.listen((_) {});
      ws.add(
        jsonEncode({
          'type': 'identify',
          'data': <String, dynamic>{
            'deviceId': 'ws-missing-token-device',
            'deviceName': 'WS Missing Token Device',
          },
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      await ws.done.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      expect(ws.closeCode, equals(4001));
      expect(ws.closeReason, contains('Authentication required'));
    });

    test('websocket identify with invalid session closes deterministically',
        () async {
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
          'username': 'ws-invalid-user',
          'password': 'ws-invalid-pass',
        },
      );
      expect(registerResponse.statusCode, 200);

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/api/ws');
      final subscription = ws.listen((_) {});
      ws.add(
        jsonEncode({
          'type': 'identify',
          'data': <String, dynamic>{
            'deviceId': 'ws-invalid-session-device',
            'deviceName': 'WS Invalid Session Device',
            'sessionToken': 'invalid-token',
          },
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      await ws.done.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      expect(ws.closeCode, equals(4001));
      expect(ws.closeReason, contains('Session expired or invalid'));
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
          'appVersion': '4.3.0',
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
          'appVersion': '4.3.0',
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
          'appVersion': '4.3.0',
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

Future<void> _writeAudioStub(String filePath) async {
  final file = File(filePath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.filled(1024 * 1024, 0), flush: true);
}

class _SlowDownloadTranscodingService extends TranscodingService {
  _SlowDownloadTranscodingService({
    required this.delay,
  }) : super(cacheDirectory: Directory.systemTemp.path);

  final Duration delay;

  @override
  Future<bool> isSonicAvailable() async => true;

  @override
  Future<DownloadTranscodeResult?> getDownloadTranscode(
    String sourcePath,
    String songId,
    QualityPreset quality,
  ) async {
    await Future<void>.delayed(delay);
    return null;
  }
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
