import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:ariami_core/ariami_core.dart';

class _LoginInfo {
  final String sessionToken;
  final String userId;

  _LoginInfo({
    required this.sessionToken,
    required this.userId,
  });
}

class _DownloadResult {
  final bool success;
  final int? statusCode;
  final int bytes;
  final Duration duration;
  final String? error;

  _DownloadResult({
    required this.success,
    required this.statusCode,
    required this.bytes,
    required this.duration,
    this.error,
  });
}

class _BatchStats {
  final int total;
  final int successes;
  final int failures;
  final int totalBytes;
  final Duration elapsed;
  final Map<int, int> statusCounts;

  _BatchStats({
    required this.total,
    required this.successes,
    required this.failures,
    required this.totalBytes,
    required this.elapsed,
    required this.statusCounts,
  });

  double get mbPerSecond {
    if (elapsed.inMilliseconds == 0) return 0;
    return (totalBytes / (1024 * 1024)) / (elapsed.inMilliseconds / 1000.0);
  }
}

class _Semaphore {
  _Semaphore(this._permits);

  int _permits;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() async {
    if (_permits > 0) {
      _permits--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) {
        next.complete();
      }
      return;
    }
    _permits++;
  }
}

void main() {
  for (final simulatedUsers in <int>[1, 5, 20]) {
    test('download benchmark ($simulatedUsers users, auth mode)', () async {
      await _runDownloadBenchmark(simulatedUsers: simulatedUsers);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

Future<void> _runDownloadBenchmark({required int simulatedUsers}) async {
  if (simulatedUsers < 1) {
    throw ArgumentError.value(
      simulatedUsers,
      'simulatedUsers',
      'must be >= 1',
    );
  }

    final envMusicFolder = Platform.environment['ARIAMI_MUSIC_FOLDER'];
    final useRealMusicFolder = envMusicFolder != null && envMusicFolder.isNotEmpty;
    final tempDir = useRealMusicFolder
        ? null
        : await Directory.systemTemp.createTemp('ariami_download_bench_');
    final authDir = await Directory.systemTemp.createTemp('ariami_auth_');
    addTearDown(() async {
      await authDir.delete(recursive: true);
      if (tempDir != null) {
        await tempDir.delete(recursive: true);
      }
    });

    final libraryManager = LibraryManager();
    final musicFolderPath = useRealMusicFolder ? envMusicFolder : tempDir!.path;
    if (useRealMusicFolder) {
      final dir = Directory(musicFolderPath);
      if (!await dir.exists()) {
        throw StateError('Music folder not found: $musicFolderPath');
      }
    } else {
      await _createDummyAudioFiles(
        tempDir,
        count: 20,
        sizeBytes: 2 * 1024 * 1024,
      );
    }

    await libraryManager.scanMusicFolder(musicFolderPath);

    final server = AriamiHttpServer();
    server.setMusicFolderPath(musicFolderPath);
    server.setDownloadLimits(
      maxConcurrent: 12,
      maxQueue: 120,
      maxConcurrentPerUser: 6,
      maxQueuePerUser: 80,
    );
    await server.initializeAuth(
      usersFilePath: p.join(authDir.path, 'users.json'),
      sessionsFilePath: p.join(authDir.path, 'sessions.json'),
      forceReinitialize: true,
    );

    final port = await _findFreePort();
    await server.start(
      advertisedIp: '127.0.0.1',
      bindAddress: '127.0.0.1',
      port: port,
    );

    final baseUri = Uri.parse('http://127.0.0.1:$port/api');
    final client = HttpClient()..maxConnectionsPerHost = 16;

    try {
      final users = <_LoginInfo>[];
      for (var i = 0; i < simulatedUsers; i++) {
        users.add(await _registerAndLogin(
          client,
          baseUri,
          username: 'user_$i',
          password: 'pass_$i',
          deviceId: 'device_$i',
          deviceName: 'Device $i',
        ));
      }

      final library = libraryManager.library;
      if (library == null || library.totalSongs == 0) {
        throw StateError('No songs found in music folder: $musicFolderPath');
      }
      final songIds = _collectSongIds(library);

      final requestsPerUser = int.tryParse(
            Platform.environment['ARIAMI_DOWNLOAD_REQUESTS_PER_USER'] ?? '',
          ) ??
          40;
      final concurrencyPerUser = int.tryParse(
            Platform.environment['ARIAMI_DOWNLOAD_CONCURRENCY'] ?? '',
          ) ??
          6;

      final overallStopwatch = Stopwatch()..start();
      final results = await Future.wait(
        users.map((user) {
          return _runUserDownloadBatch(
            client,
            baseUri,
            sessionToken: user.sessionToken,
            songIds: songIds,
            requests: requestsPerUser,
            concurrency: concurrencyPerUser,
          );
        }),
      );
      overallStopwatch.stop();

      final combined = _combineStats(results, overallStopwatch.elapsed);
      _printStats('Combined ($simulatedUsers users)', combined);
      for (var i = 0; i < results.length; i++) {
        _printStats('User $i', results[i]);
      }

      expect(combined.total, requestsPerUser * simulatedUsers);
      expect(combined.successes, greaterThan(0));
    } finally {
      client.close(force: true);
      await server.stop();
    }
}

Future<List<File>> _createDummyAudioFiles(
  Directory? directory, {
  required int count,
  required int sizeBytes,
}) async {
  if (directory == null) return <File>[];
  final files = <File>[];
  for (var i = 0; i < count; i++) {
    final file = File(p.join(directory.path, 'Track_$i.mp3'));
    final raf = await file.open(mode: FileMode.write);
    await raf.truncate(sizeBytes + (i * 1024));
    await raf.close();
    files.add(file);
  }
  return files;
}

String _songIdForPath(String filePath) {
  final bytes = utf8.encode(filePath);
  final hash = md5.convert(bytes).toString();
  return hash.substring(0, 12);
}

List<String> _collectSongIds(LibraryStructure library) {
  final ids = <String>{};
  for (final album in library.albums.values) {
    for (final song in album.songs) {
      ids.add(_songIdForPath(song.filePath));
    }
  }
  for (final song in library.standaloneSongs) {
    ids.add(_songIdForPath(song.filePath));
  }
  return ids.toList();
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_LoginInfo> _registerAndLogin(
  HttpClient client,
  Uri baseUri, {
  required String username,
  required String password,
  required String deviceId,
  required String deviceName,
}) async {
  await _postJson(
    client,
    baseUri.resolve('/api/auth/register'),
    {
      'username': username,
      'password': password,
    },
  );

  final loginResponse = await _postJson(
    client,
    baseUri.resolve('/api/auth/login'),
    {
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
    },
  );

  return _LoginInfo(
    sessionToken: loginResponse['sessionToken'] as String,
    userId: loginResponse['userId'] as String,
  );
}

Future<_BatchStats> _runUserDownloadBatch(
  HttpClient client,
  Uri baseUri, {
  required String sessionToken,
  required List<String> songIds,
  required int requests,
  required int concurrency,
}) async {
  final semaphore = _Semaphore(concurrency);
  final results = <_DownloadResult>[];
  final stopwatch = Stopwatch()..start();

  final tasks = List.generate(requests, (index) {
    final songId = songIds[index % songIds.length];
    return () async {
      await semaphore.acquire();
      try {
        final result = await _downloadSong(
          client,
          baseUri,
          sessionToken: sessionToken,
          songId: songId,
        );
        results.add(result);
      } finally {
        semaphore.release();
      }
    }();
  });

  await Future.wait(tasks);
  stopwatch.stop();
  return _summarize(results, stopwatch.elapsed);
}

Future<_DownloadResult> _downloadSong(
  HttpClient client,
  Uri baseUri, {
  required String sessionToken,
  required String songId,
}) async {
  final start = Stopwatch()..start();
  try {
    final ticketResponse = await _postJson(
      client,
      baseUri.resolve('/api/stream-ticket'),
      {'songId': songId},
      authToken: sessionToken,
    );
    final streamToken = ticketResponse['streamToken'] as String;

    final downloadUri = baseUri.resolve('/api/download/$songId')
        .replace(queryParameters: {'streamToken': streamToken});

    final request = await client.getUrl(downloadUri);
    final response = await request.close();

    int bytes = 0;
    await for (final chunk in response) {
      bytes += chunk.length;
    }
    start.stop();

    return _DownloadResult(
      success: response.statusCode == 200,
      statusCode: response.statusCode,
      bytes: bytes,
      duration: start.elapsed,
    );
  } catch (e) {
    start.stop();
    return _DownloadResult(
      success: false,
      statusCode: null,
      bytes: 0,
      duration: start.elapsed,
      error: e.toString(),
    );
  }
}

Future<Map<String, dynamic>> _postJson(
  HttpClient client,
  Uri uri,
  Map<String, dynamic> payload, {
  String? authToken,
}) async {
  final request = await client.postUrl(uri);
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
  if (authToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
  }
  request.add(utf8.encode(jsonEncode(payload)));

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Request failed (${response.statusCode}): $body', uri: uri);
  }

  return jsonDecode(body) as Map<String, dynamic>;
}

_BatchStats _summarize(List<_DownloadResult> results, Duration elapsed) {
  final statusCounts = <int, int>{};
  int successes = 0;
  int failures = 0;
  int bytes = 0;

  for (final result in results) {
    if (result.success) {
      successes++;
      bytes += result.bytes;
    } else {
      failures++;
    }
    if (result.statusCode != null) {
      statusCounts[result.statusCode!] =
          (statusCounts[result.statusCode!] ?? 0) + 1;
    }
  }

  return _BatchStats(
    total: results.length,
    successes: successes,
    failures: failures,
    totalBytes: bytes,
    elapsed: elapsed,
    statusCounts: statusCounts,
  );
}

_BatchStats _combineStats(List<_BatchStats> batches, Duration elapsed) {
  int total = 0;
  int successes = 0;
  int failures = 0;
  int bytes = 0;
  final statusCounts = <int, int>{};

  for (final batch in batches) {
    total += batch.total;
    successes += batch.successes;
    failures += batch.failures;
    bytes += batch.totalBytes;
    for (final entry in batch.statusCounts.entries) {
      statusCounts[entry.key] = (statusCounts[entry.key] ?? 0) + entry.value;
    }
  }

  return _BatchStats(
    total: total,
    successes: successes,
    failures: failures,
    totalBytes: bytes,
    elapsed: elapsed,
    statusCounts: statusCounts,
  );
}

void _printStats(String label, _BatchStats stats) {
  final mb = stats.totalBytes / (1024 * 1024);
  print(
      '[$label] total=${stats.total} success=${stats.successes} fail=${stats.failures} '
      'bytes=${mb.toStringAsFixed(2)}MB elapsed=${stats.elapsed.inMilliseconds}ms '
      'throughput=${stats.mbPerSecond.toStringAsFixed(2)}MB/s '
      'status=${stats.statusCounts}');
}
