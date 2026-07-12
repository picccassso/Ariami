import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/tailscale_path_diagnostics.dart';
import 'package:test/test.dart';

void main() {
  test('logs aggregate direct and relay counts without peer identity',
      () async {
    final logs = <String>[];
    final diagnostics = TailscalePathDiagnostics(
      processRunner: (_, arguments) async {
        expect(arguments, <String>['status', '--json']);
        return ProcessResult(
          1,
          0,
          jsonEncode(<String, dynamic>{
            'Peer': <String, dynamic>{
              'secret-peer-key-1': <String, dynamic>{
                'HostName': 'private-phone-name',
                'Active': true,
                'CurAddr': '203.0.113.4:1234',
                'Relay': '',
              },
              'secret-peer-key-2': <String, dynamic>{
                'HostName': 'private-laptop-name',
                'Active': true,
                'CurAddr': '',
                'Relay': 'lhr',
              },
            },
          }),
          '',
        );
      },
      logger: logs.add,
    );

    await diagnostics.sample();

    expect(logs, hasLength(1));
    expect(logs.single, contains('"activeDirect":1'));
    expect(logs.single, contains('"activeRelay":1'));
    expect(logs.single, isNot(contains('private-phone-name')));
    expect(logs.single, isNot(contains('secret-peer-key')));
  });

  test('missing CLI is silent and non-fatal', () async {
    final logs = <String>[];
    final diagnostics = TailscalePathDiagnostics(
      processRunner: (_, __) async =>
          throw const ProcessException('tailscale', <String>[]),
      logger: logs.add,
    );

    await diagnostics.sample();

    expect(logs, isEmpty);
  });
}
