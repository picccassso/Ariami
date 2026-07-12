import 'dart:convert';

import 'package:ariami_core/services/license/license_key_activator.dart';
import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/screens/settings/tv_license_screen.dart';
import 'package:ariami_mobile/services/api/api_client.dart';
import 'package:ariami_mobile/services/license/tv_license_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
      : super(
          serverInfo: ServerInfo(
            server: '127.0.0.1',
            port: 9,
            name: 'Test Server',
            version: 'test',
          ),
        );

  String? uploaded;

  @override
  Future<void> putLicenseFile(String licenseFile) async {
    uploaded = licenseFile;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(TvLicenseService service) {
    return MaterialApp(home: TvLicenseScreen(service: service));
  }

  TvLicenseService serviceWith(http.Client worker, _FakeApiClient? api) {
    return TvLicenseService(
      activator: LicenseKeyActivator(
        baseUrl: 'https://worker.test',
        httpClient: worker,
      ),
      apiClientProvider: () => api,
      deviceNameProvider: () async => 'Test Phone',
    );
  }

  testWidgets('activates a key and shows the success state', (tester) async {
    final worker = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'licenseFile': 'OPAQUE.tv-blob.sig',
          'products': ['tv'],
        }),
        200,
      );
    });
    final api = _FakeApiClient();

    await tester.pumpWidget(wrap(serviceWith(worker, api)));
    await tester.enterText(find.byType(TextField), 'TV-KEY-1');
    await tester.tap(find.text('Activate TV license'));
    await tester.pumpAndSettle();

    expect(api.uploaded, 'OPAQUE.tv-blob.sig');
    expect(find.textContaining('TV license activated'), findsOneWidget);
    // The field clears so the key can't be double-submitted by accident.
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
  });

  testWidgets('shows the shared error copy on failure', (tester) async {
    final worker = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'code': 'INVALID_KEY', 'message': 'nope'},
        }),
        404,
      );
    });

    await tester.pumpWidget(wrap(serviceWith(worker, _FakeApiClient())));
    await tester.enterText(find.byType(TextField), 'BAD-KEY');
    await tester.tap(find.text('Activate TV license'));
    await tester.pumpAndSettle();

    expect(find.textContaining('wasn\'t recognized'), findsOneWidget);
  });

  testWidgets('an empty key never reaches the network', (tester) async {
    var workerCalled = false;
    final worker = MockClient((request) async {
      workerCalled = true;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(wrap(serviceWith(worker, _FakeApiClient())));
    await tester.tap(find.text('Activate TV license'));
    await tester.pumpAndSettle();

    expect(workerCalled, isFalse);
    expect(find.textContaining('Enter your license key'), findsOneWidget);
  });
}
