import 'dart:io';

/// Raspberry Pi detection shared by the transcoding policy, the CLI runtime
/// policy and the desktop download limits.
class DeviceModel {
  const DeviceModel._();

  /// Files probed (in order) for the host's device model.
  static const defaultModelPaths = <String>[
    '/proc/device-tree/model',
    '/sys/firmware/devicetree/base/model',
    '/proc/cpuinfo',
  ];

  /// True on Linux ARM hosts. Unrecognized Linux ARM devices are conservatively
  /// treated as Raspberry Pi class (low-power) hosts.
  static bool isRaspberryPi() {
    if (!Platform.isLinux) return false;
    final arch = Platform.version.toLowerCase();
    return arch.contains('arm') || arch.contains('aarch64');
  }

  /// Lowercased device model text when it identifies a Raspberry Pi.
  ///
  /// [isLinux] overrides the platform check; [readFile] overrides file access.
  static Future<String?> raspberryPiModel({
    bool? isLinux,
    List<String> paths = defaultModelPaths,
    Future<String?> Function(String path)? readFile,
  }) async {
    if (!(isLinux ?? Platform.isLinux)) {
      return null;
    }

    final reader = readFile ?? _readFileOrNull;
    for (final path in paths) {
      final content = await reader(path);
      if (content == null || content.isEmpty) {
        continue;
      }
      final normalized = content.toLowerCase();
      if (normalized.contains('raspberry')) {
        return normalized;
      }
      if (path.contains('cpuinfo') && normalized.contains('bcm')) {
        return normalized;
      }
    }

    return null;
  }

  /// True when the detected model is `Raspberry Pi <generation>`.
  static Future<bool> isRaspberryPiGeneration(
    int generation, {
    bool? isLinux,
    List<String> paths = defaultModelPaths,
    Future<String?> Function(String path)? readFile,
  }) async {
    final model = await raspberryPiModel(
      isLinux: isLinux,
      paths: paths,
      readFile: readFile,
    );
    return model != null && model.contains('raspberry pi $generation');
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
