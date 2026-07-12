import 'dart:convert';

import 'package:ariami_core/services/license/license_key_activator.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/services/license/tv_license_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.putError})
      : super(
          serverInfo: ServerInfo(
            server: '127.0.0.1',
            port: 9,
            name: 'Test Server',
            version: 'test',
          ),
        );

  final ApiException? putError;
  String? uploaded;

  @override
  Future<void> putLicenseFile(String licenseFile) async {
    final error = putError;
    if (error != null) throw error;
    uploaded = licenseFile;
  }
}

void main() {
  TvLicenseService service({
    required http.Client worker,
    _FakeApiClient? apiClient,
    String? deviceName = 'Test Phone',
  }) {
    return TvLicenseService(
      activator: LicenseKeyActivator(
        baseUrl: 'https://worker.test',
        httpClient: worker,
      ),
      apiClientProvider: () => apiClient,
      deviceNameProvider: () async => deviceName,
    );
  }

  MockClient workerReturningFile({List<String> products = const ['tv']}) {
    return MockClient((request) async {
      expect(request.url.path, '/v1/activate');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['product'], 'tv');
      return http.Response(
        jsonEncode({
          'licenseFile': 'OPAQUE.tv-blob.sig',
          'instanceId': 'inst-1',
          'products': products,
        }),
        200,
      );
    });
  }

  test('activates the key and relays the file to the server', () async {
    final api = _FakeApiClient();
    final tv = service(worker: workerReturningFile(), apiClient: api);
    final error = await tv.activateKey('TV-KEY-1');
    expect(error, isNull);
    expect(api.uploaded, 'OPAQUE.tv-blob.sig');
  });

  test('requires a server connection before calling the worker', () async {
    var workerCalled = false;
    final worker = MockClient((request) async {
      workerCalled = true;
      return http.Response('{}', 200);
    });
    final tv = service(worker: worker, apiClient: null);
    final error = await tv.activateKey('TV-KEY-1');
    expect(error, contains('Connect to your Ariami server'));
    expect(workerCalled, isFalse);
  });

  test('falls back to a default device name', () async {
    String? sentDeviceName;
    final worker = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      sentDeviceName = body['deviceName'] as String?;
      return http.Response(
        jsonEncode({
          'licenseFile': 'OPAQUE.tv-blob.sig',
          'products': ['tv'],
        }),
        200,
      );
    });
    final tv = service(
      worker: worker,
      apiClient: _FakeApiClient(),
      deviceName: null,
    );
    expect(await tv.activateKey('TV-KEY-1'), isNull);
    expect(sentDeviceName, 'Ariami Mobile');
  });

  test('worker failures surface the shared friendly copy', () async {
    final worker = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'code': 'WRONG_PRODUCT', 'message': 'nope'},
        }),
        403,
      );
    });
    final api = _FakeApiClient();
    final tv = service(worker: worker, apiClient: api);
    final error = await tv.activateKey('DESKTOP-KEY');
    expect(error, contains('doesn\'t include Ariami TV'));
    expect(api.uploaded, isNull);
  });

  test('a key whose plaintext products omit tv is refused before upload',
      () async {
    final api = _FakeApiClient();
    final tv = service(
      worker: workerReturningFile(products: ['desktop']),
      apiClient: api,
    );
    final error = await tv.activateKey('DESKTOP-KEY');
    expect(error, contains('doesn\'t include Ariami TV'));
    expect(api.uploaded, isNull);
  });

  test('a non-admin session maps FORBIDDEN_ADMIN to an owner hint', () async {
    final api = _FakeApiClient(
      putError: ApiException(code: 'FORBIDDEN_ADMIN', message: 'forbidden'),
    );
    final tv = service(worker: workerReturningFile(), apiClient: api);
    final error = await tv.activateKey('TV-KEY-1');
    expect(error, contains('owner'));
  });

  test('other upload failures report a storage problem', () async {
    final api = _FakeApiClient(
      putError: ApiException(code: 'SERVER_ERROR', message: 'boom'),
    );
    final tv = service(worker: workerReturningFile(), apiClient: api);
    final error = await tv.activateKey('TV-KEY-1');
    expect(error, contains('couldn\'t be stored'));
  });
}
