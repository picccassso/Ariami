import 'dart:io';

class DesktopDownloadLimits {
  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

  const DesktopDownloadLimits({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
  });
}

class DesktopDownloadLimitsService {
  static const DesktopDownloadLimits _macosLimits = DesktopDownloadLimits(
    maxConcurrent: 30,
    maxQueue: 400,
    maxConcurrentPerUser: 10,
    maxQueuePerUser: 200,
  );

  static const DesktopDownloadLimits _defaultDesktopLimits =
      DesktopDownloadLimits(
    maxConcurrent: 10,
    maxQueue: 120,
    maxConcurrentPerUser: 3,
    maxQueuePerUser: 50,
  );

  // Raspberry Pi 5 can sustain higher per-user concurrency than generic Linux
  // desktop defaults, so expose the higher slot count to mobile clients.
  static const DesktopDownloadLimits _pi5Limits = DesktopDownloadLimits(
    maxConcurrent: 10,
    maxQueue: 120,
    maxConcurrentPerUser: 6,
    maxQueuePerUser: 50,
  );

  static Future<DesktopDownloadLimits> resolve({
    bool? isMacOS,
    bool? isLinux,
    Future<String?> Function(String path)? readFile,
  }) async {
    final macOS = isMacOS ?? Platform.isMacOS;
    if (macOS) {
      return _macosLimits;
    }

    final linux = isLinux ?? Platform.isLinux;
    if (!linux) {
      return _defaultDesktopLimits;
    }

    if (await _isRaspberryPi5(readFile: readFile)) {
      return _pi5Limits;
    }
    return _defaultDesktopLimits;
  }

  static Future<bool> _isRaspberryPi5({
    Future<String?> Function(String path)? readFile,
  }) async {
    final reader = readFile ?? _readFileOrNull;
    final candidates = <String>[
      '/proc/device-tree/model',
      '/sys/firmware/devicetree/base/model',
      '/proc/cpuinfo',
    ];

    for (final path in candidates) {
      final content = await reader(path);
      if (content == null || content.isEmpty) {
        continue;
      }
      if (_looksLikePi5(content)) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikePi5(String value) {
    return value.toLowerCase().contains('raspberry pi 5');
  }

  static Future<String?> _readFileOrNull(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }
}
