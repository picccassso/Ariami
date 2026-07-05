import 'package:ariami_cli/server_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('notifyHttpServerReady', () {
    test('invokes callback with port when provided', () async {
      int? calledPort;
      var callCount = 0;

      await notifyHttpServerReady((port) async {
        calledPort = port;
        callCount++;
      }, 9090);

      expect(calledPort, 9090);
      expect(callCount, 1);
    });

    test('does nothing when callback is null', () async {
      await notifyHttpServerReady(null, 8080);
    });
  });

  group('buildServerModeTransitionResponse', () {
    test('reports foreground server-mode setup can continue', () async {
      final response = await buildServerModeTransitionResponse();

      expect(response['success'], isTrue);
      expect(response['alreadyInForeground'], isTrue);
      expect(response['message'], contains('foreground'));
      expect(response['message'], contains('Setup can continue'));
    });
  });
}
