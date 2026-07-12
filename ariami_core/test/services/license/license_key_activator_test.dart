import 'dart:convert';

import 'package:ariami_core/services/license/license_key_activator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  LicenseKeyActivator activator(MockClient client) =>
      LicenseKeyActivator(baseUrl: 'https://worker.test', httpClient: client);

  test('sends key, device name and product; returns the license file',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'licenseFile': 'OPAQUE.blob.sig',
          'instanceId': 'inst-1',
          'products': ['tv'],
          'maxMajorVersion': 5,
        }),
        200,
      );
    });

    final result = await activator(client).activate(
      licenseKey: '  ABCD-1234  ',
      product: 'tv',
      deviceName: 'Test Phone',
    );

    expect(captured.url.toString(), 'https://worker.test/v1/activate');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['licenseKey'], 'ABCD-1234');
    expect(body['deviceName'], 'Test Phone');
    expect(body['product'], 'tv');
    expect(result, isA<LicenseKeyActivationSuccess>());
    expect(
      (result as LicenseKeyActivationSuccess).licenseFile,
      'OPAQUE.blob.sig',
    );
  });

  test('empty key fails without any network call', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final result = await activator(client).activate(
      licenseKey: '   ',
      product: 'tv',
      deviceName: 'Test Phone',
    );
    expect(calls, 0);
    expect(
      (result as LicenseKeyActivationFailure).error,
      LicenseKeyActivationError.emptyKey,
    );
  });

  test('maps service error codes', () async {
    Future<LicenseKeyActivationError> errorFor(
      int status,
      String code,
    ) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': code, 'message': 'nope'},
          }),
          status,
        );
      });
      final result = await activator(client).activate(
        licenseKey: 'ABCD-1234',
        product: 'tv',
        deviceName: 'Test Phone',
      );
      return (result as LicenseKeyActivationFailure).error;
    }

    expect(
      await errorFor(404, 'INVALID_KEY'),
      LicenseKeyActivationError.invalidKey,
    );
    expect(
      await errorFor(409, 'ACTIVATION_LIMIT'),
      LicenseKeyActivationError.activationLimit,
    );
    expect(
      await errorFor(403, 'KEY_DISABLED'),
      LicenseKeyActivationError.keyDisabled,
    );
    expect(
      await errorFor(403, 'WRONG_PRODUCT'),
      LicenseKeyActivationError.wrongProduct,
    );
    expect(
      await errorFor(429, 'RATE_LIMITED'),
      LicenseKeyActivationError.rateLimited,
    );
    expect(
      await errorFor(500, 'SOMETHING_NEW'),
      LicenseKeyActivationError.serviceError,
    );
  });

  test('a 200 whose products omit the requested product is wrongProduct',
      () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'licenseFile': 'OPAQUE.blob.sig',
          'products': ['desktop'],
        }),
        200,
      );
    });
    final result = await activator(client).activate(
      licenseKey: 'ABCD-1234',
      product: 'tv',
      deviceName: 'Test Phone',
    );
    expect(
      (result as LicenseKeyActivationFailure).error,
      LicenseKeyActivationError.wrongProduct,
    );
  });

  test('a 200 without a products list is trusted (older service)', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'licenseFile': 'OPAQUE.blob.sig'}), 200);
    });
    final result = await activator(client).activate(
      licenseKey: 'ABCD-1234',
      product: 'tv',
      deviceName: 'Test Phone',
    );
    expect(result, isA<LicenseKeyActivationSuccess>());
  });

  test('network failure maps to unreachable', () async {
    final client = MockClient((request) async {
      throw http.ClientException('boom');
    });
    final result = await activator(client).activate(
      licenseKey: 'ABCD-1234',
      product: 'tv',
      deviceName: 'Test Phone',
    );
    expect(
      (result as LicenseKeyActivationFailure).error,
      LicenseKeyActivationError.unreachable,
    );
  });

  test('garbage body maps to serviceError', () async {
    final client = MockClient((request) async {
      return http.Response('<!doctype html>', 200);
    });
    final result = await activator(client).activate(
      licenseKey: 'ABCD-1234',
      product: 'tv',
      deviceName: 'Test Phone',
    );
    expect(
      (result as LicenseKeyActivationFailure).error,
      LicenseKeyActivationError.serviceError,
    );
  });

  test('failure messages parameterize the product label', () {
    const failure =
        LicenseKeyActivationFailure(LicenseKeyActivationError.wrongProduct);
    expect(failure.message('Ariami TV'), contains('Ariami TV'));
  });
}
