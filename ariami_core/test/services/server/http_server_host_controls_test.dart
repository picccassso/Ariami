import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/host_controls.dart';
import 'package:ariami_core/services/auth/auth_service.dart';
import 'package:ariami_core/services/reset/reset_service.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'http_server_test_support.dart';

void main() {
  late AriamiHttpServer server;
  late Directory directory;
  late int port;
  late String adminToken;
  late String memberToken;

  /// Recorded calls, so each test can assert what the host was actually asked
  /// to do rather than only what it answered.
  bool? lastAutostartRequest;
  ResetScope? lastResetScope;
  var autostartEnabled = false;

  setUp(() async {
    server = AriamiHttpServer();
    await server.stop();
    server.libraryManager.clear();
    lastAutostartRequest = null;
    lastResetScope = null;
    autostartEnabled = false;

    directory =
        await Directory.systemTemp.createTemp('ariami_http_host_controls_');
    server.libraryManager
        .setCachePath(p.join(directory.path, 'metadata_cache.json'));
    await server.initializeAuth(
      usersFilePath: p.join(directory.path, 'users.json'),
      sessionsFilePath: p.join(directory.path, 'sessions.json'),
      forceReinitialize: true,
    );
    // First registered user is the admin.
    await AuthService().register('owner', 'owner-pass-123456');
    await AuthService().register('member', 'member-pass-123456');
    port = await startHttpTestServer(server);
    adminToken = await _login(port, 'owner', 'owner-pass-123456', 'device-o');
    memberToken =
        await _login(port, 'member', 'member-pass-123456', 'device-m');
  });

  tearDown(() async {
    // Leave the shared singleton without callbacks so other suites still see
    // a host that does not offer these controls.
    server.setHostControlCallbacks();
    await server.stop();
    server.libraryManager.clear();
    await directory.delete(recursive: true);
  });

  HostControlsSnapshot snapshot() => HostControlsSnapshot(
        musicFolderPath: '/srv/music',
        autostartSupported: true,
        autostartEnabled: autostartEnabled,
        resetSupported: true,
      );

  void registerCallbacks() {
    server.setHostControlCallbacks(
      getSnapshot: () async => snapshot(),
      setAutostartEnabled: (enabled) async {
        lastAutostartRequest = enabled;
        autostartEnabled = enabled;
        return snapshot();
      },
      reset: (scope) async {
        lastResetScope = scope;
        return const HostResetOutcome(success: true, message: 'Reset done.');
      },
    );
  }

  group('without host controls registered', () {
    test('every endpoint reports NOT_CONFIGURED rather than failing', () async {
      final get = await _request(port, 'GET', '/api/admin/host-controls',
          token: adminToken);
      final autostart = await _request(port, 'POST', '/api/admin/autostart',
          token: adminToken, body: {'enabled': true});
      final reset = await _request(port, 'POST', '/api/admin/reset',
          token: adminToken, body: {'scope': 'setup'});

      for (final response in [get, autostart, reset]) {
        expect(response.statusCode, 503);
        expect(response.json['error']['code'], 'NOT_CONFIGURED');
      }
    });
  });

  group('with host controls registered', () {
    setUp(registerCallbacks);

    test('endpoints require authentication', () async {
      final get = await _request(port, 'GET', '/api/admin/host-controls');
      expect(get.statusCode, 401);
    });

    test('endpoints are admin-only', () async {
      final get = await _request(port, 'GET', '/api/admin/host-controls',
          token: memberToken);
      final autostart = await _request(port, 'POST', '/api/admin/autostart',
          token: memberToken, body: {'enabled': true});
      final reset = await _request(port, 'POST', '/api/admin/reset',
          token: memberToken, body: {'scope': 'factory'});

      expect(get.statusCode, 403);
      expect(autostart.statusCode, 403);
      expect(reset.statusCode, 403);
      expect(lastAutostartRequest, isNull);
      expect(lastResetScope, isNull);
    });

    test('GET reports the host snapshot', () async {
      final response = await _request(port, 'GET', '/api/admin/host-controls',
          token: adminToken);

      expect(response.statusCode, 200);
      final parsed = HostControlsSnapshot.fromJson(response.json);
      expect(parsed.musicFolderPath, '/srv/music');
      expect(parsed.autostartSupported, isTrue);
      expect(parsed.autostartEnabled, isFalse);
      expect(parsed.resetSupported, isTrue);
    });

    test('POST autostart applies the value and returns a fresh snapshot',
        () async {
      final response = await _request(port, 'POST', '/api/admin/autostart',
          token: adminToken, body: {'enabled': true});

      expect(response.statusCode, 200);
      expect(lastAutostartRequest, isTrue);
      expect(HostControlsSnapshot.fromJson(response.json).autostartEnabled,
          isTrue);
    });

    test('POST autostart rejects a non-boolean value', () async {
      final response = await _request(port, 'POST', '/api/admin/autostart',
          token: adminToken, body: {'enabled': 'yes'});

      expect(response.statusCode, 400);
      expect(response.json['error']['code'], 'INVALID_REQUEST');
      expect(lastAutostartRequest, isNull);
    });

    test('POST reset maps the scope name onto ResetScope', () async {
      final setup = await _request(port, 'POST', '/api/admin/reset',
          token: adminToken, body: {'scope': 'setup'});
      expect(setup.statusCode, 200);
      expect(lastResetScope, ResetScope.setupOnly);
      expect(HostResetOutcome.fromJson(setup.json).success, isTrue);

      final factory = await _request(port, 'POST', '/api/admin/reset',
          token: adminToken, body: {'scope': 'factory'});
      expect(factory.statusCode, 200);
      expect(lastResetScope, ResetScope.factoryReset);
    });

    test('POST reset refuses an unknown or missing scope', () async {
      // A reset that guesses at its own scope could clear far more than the
      // caller intended, so the scope is never defaulted.
      final unknown = await _request(port, 'POST', '/api/admin/reset',
          token: adminToken, body: {'scope': 'everything'});
      final missing = await _request(port, 'POST', '/api/admin/reset',
          token: adminToken, body: <String, dynamic>{});

      expect(unknown.statusCode, 400);
      expect(missing.statusCode, 400);
      expect(lastResetScope, isNull);
    });
  });
}

Future<String> _login(
  int port,
  String username,
  String password,
  String deviceId,
) async {
  final response = await _request(
    port,
    'POST',
    '/api/auth/login',
    body: {
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceId,
    },
  );
  expect(response.statusCode, 200);
  return response.json['sessionToken'] as String;
}

Future<_Response> _request(
  int port,
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return _Response(
      response.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response(this.statusCode, this.json);
  final int statusCode;
  final Map<String, dynamic> json;
}
