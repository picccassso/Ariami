import 'dart:convert';
import 'dart:io';

import 'package:ariami_cli/services/cli_state_service.dart';
import 'package:ariami_cli/services/server_setup_callbacks.dart';
import 'package:ariami_core/ariami_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ServerSetupCallbacks library rescans', () {
    late AriamiHttpServer server;
    late Directory testDir;
    late Directory musicDir;
    late int port;

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('ariami_cli_rescan_');
      musicDir = await Directory(p.join(testDir.path, 'music')).create();

      server = AriamiHttpServer();
      await server.stop();
      server.libraryManager.clear();
      server.libraryManager.setCachePath(
        p.join(testDir.path, 'metadata_cache.json'),
      );

      ServerSetupCallbacks(
        httpServer: server,
        stateService: CliStateService(),
        getMusicFolderPath: () async => musicDir.path,
      ).register();

      port = await _findFreePort();
      await server.start(
        advertisedIp: '127.0.0.1',
        bindAddress: '127.0.0.1',
        port: port,
      );
    });

    tearDown(() async {
      await server.stop();
      server.libraryManager.clear();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('web rescan replaces the library with current folder contents',
        () async {
      final removedPath = p.join(musicDir.path, 'removed.mp3');
      await _writeAudioStub(removedPath, fillByte: 1);

      final firstStart = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/start-scan'),
      );
      expect(firstStart['success'], isTrue);

      final firstStatus = await _waitForScan(port);
      expect(firstStatus['songsFound'], 1);
      final firstScanTime = server.libraryManager.lastScanTime;
      expect(firstScanTime, isNotNull);

      await File(removedPath).delete();
      await _writeAudioStub(
        p.join(musicDir.path, 'added-one.mp3'),
        fillByte: 2,
      );
      await _writeAudioStub(
        p.join(musicDir.path, 'added-two.mp3'),
        fillByte: 3,
      );

      final secondStart = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/start-scan'),
      );
      expect(secondStart['success'], isTrue);

      final secondStatus = await _waitForScan(port);
      expect(secondStatus['songsFound'], 2);
      expect(secondStatus['scanError'], isNull);
      expect(secondStatus['skippedFileCount'], 0);
      expect(secondStatus['failedFiles'], isEmpty);
      expect(server.libraryManager.lastScanTime, isNot(firstScanTime));
    });

    test('web rescan reports a folder failure instead of claiming success',
        () async {
      await musicDir.delete(recursive: true);

      final start = await _postJson(
        Uri.parse('http://127.0.0.1:$port/api/setup/start-scan'),
      );
      expect(start['success'], isFalse);

      final status = await _waitForScan(port);
      expect(status['scanError'], isNotEmpty);
      expect(status['currentStatus'], contains('Scan failed'));
      expect(server.libraryManager.lastScanTime, isNull);
    });
  });
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<Map<String, dynamic>> _postJson(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    request.write('{}');
    final response = await request.close();
    final bodyText = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: bodyText);
    return jsonDecode(bodyText) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _getJson(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final bodyText = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: bodyText);
    return jsonDecode(bodyText) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _waitForScan(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final status = await _getJson(
      Uri.parse('http://127.0.0.1:$port/api/setup/scan-status'),
    );
    if (status['isScanning'] != true) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for library scan');
}

Future<void> _writeAudioStub(String filePath, {required int fillByte}) async {
  final file = File(filePath);
  await file.writeAsBytes(List<int>.filled(1024, fillByte), flush: true);
}
