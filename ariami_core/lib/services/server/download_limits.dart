import 'dart:io';

/// Download concurrency/queue limits advertised by a server host.
class DownloadLimits {
  final int maxConcurrent;
  final int maxQueue;
  final int maxConcurrentPerUser;
  final int maxQueuePerUser;

  const DownloadLimits({
    required this.maxConcurrent,
    required this.maxQueue,
    required this.maxConcurrentPerUser,
    required this.maxQueuePerUser,
  });

  static const macos = DownloadLimits(
    maxConcurrent: 30,
    maxQueue: 400,
    maxConcurrentPerUser: 10,
    maxQueuePerUser: 200,
  );

  static const desktopDefault = DownloadLimits(
    maxConcurrent: 10,
    maxQueue: 120,
    maxConcurrentPerUser: 3,
    maxQueuePerUser: 50,
  );

  /// Presets for non-Pi hosts: macOS gets [macos], everything else
  /// [desktopDefault].
  static DownloadLimits forDesktopPlatform({bool? isMacOS}) =>
      (isMacOS ?? Platform.isMacOS) ? macos : desktopDefault;
}
