import 'dart:io';

/// Effective and configured transcode slot counts for the host server.
class TranscodeSlotsSnapshot {
  const TranscodeSlotsSnapshot({
    required this.effective,
    required this.defaultSlots,
    this.override,
    this.restartRequired = true,
  });

  /// Active slot count (override when set, otherwise [defaultSlots]).
  final int effective;

  /// Platform default before any user override.
  final int defaultSlots;

  /// User override, or null when using the platform default.
  final int? override;

  /// Whether a server restart is required for pending changes to apply.
  final bool restartRequired;

  bool get isCustom => override != null;

  Map<String, dynamic> toJson() => {
        'effective': effective,
        'defaultSlots': defaultSlots,
        'override': override,
        'restartRequired': restartRequired,
      };

  factory TranscodeSlotsSnapshot.fromJson(Map<String, dynamic> json) {
    return TranscodeSlotsSnapshot(
      effective: json['effective'] as int,
      defaultSlots: json['defaultSlots'] as int,
      override: json['override'] as int?,
      restartRequired: json['restartRequired'] as bool? ?? true,
    );
  }
}

/// Resolves platform-aware default transcode slot counts and validates overrides.
class TranscodeSlotsPolicy {
  /// Minimum allowed transcode slot count.
  static const int minSlots = 1;

  /// Default slot count for systems that are not a recognised Raspberry Pi.
  static const int desktopDefaultSlots = 6;

  /// Resolve the platform default slot count for this host.
  static Future<int> resolveDefault({
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
    bool? isRaspberryPi,
    bool? isRaspberryPi3,
    bool? isRaspberryPi4,
    bool? isRaspberryPi5,
    Future<String?> Function(String path)? readFile,
  }) async {
    final macOS = isMacOS ?? Platform.isMacOS;
    if (macOS) {
      return desktopDefaultSlots;
    }

    final windows = isWindows ?? Platform.isWindows;
    if (windows) {
      return desktopDefaultSlots;
    }

    final linux = isLinux ?? Platform.isLinux;
    if (!linux) {
      return desktopDefaultSlots;
    }

    final onPi = isRaspberryPi ?? await _isRaspberryPi(readFile: readFile);
    if (onPi) {
      final onPi5 =
          isRaspberryPi5 ?? await _isRaspberryPi5(readFile: readFile);
      if (onPi5) {
        return 5;
      }
      final onPi4 =
          isRaspberryPi4 ?? await _isRaspberryPi4(readFile: readFile);
      if (onPi4) {
        return 4;
      }
      final onPi3 =
          isRaspberryPi3 ?? await _isRaspberryPi3(readFile: readFile);
      if (onPi3) {
        return 3;
      }
      // Unrecognised / older Pi: use the most conservative supported default.
      return 3;
    }

    return desktopDefaultSlots;
  }

  /// Build a snapshot from an optional override and platform default.
  static TranscodeSlotsSnapshot resolve({
    int? override,
    required int defaultSlots,
    bool restartRequired = true,
  }) {
    if (override != null) {
      validateSlots(override);
    }

    return TranscodeSlotsSnapshot(
      effective: override ?? defaultSlots,
      defaultSlots: defaultSlots,
      override: override,
      restartRequired: restartRequired,
    );
  }

  /// Resolve default slots and combine with an optional override.
  static Future<TranscodeSlotsSnapshot> resolveSnapshot({
    int? override,
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
    Future<String?> Function(String path)? readFile,
    bool restartRequired = true,
  }) async {
    final defaultSlots = await resolveDefault(
      isMacOS: isMacOS,
      isWindows: isWindows,
      isLinux: isLinux,
      readFile: readFile,
    );
    return resolve(
      override: override,
      defaultSlots: defaultSlots,
      restartRequired: restartRequired,
    );
  }

  /// Validate a user-provided slot count.
  static void validateSlots(int slots) {
    if (slots < minSlots) {
      throw ArgumentError.value(
        slots,
        'slots',
        'must be an integer >= $minSlots',
      );
    }
  }

  static Future<bool> _isRaspberryPi({
    Future<String?> Function(String path)? readFile,
  }) async {
    if (!(Platform.isLinux)) {
      return false;
    }

    final arch = Platform.version.toLowerCase();
    final isArm = arch.contains('arm') || arch.contains('aarch64');
    if (!isArm) {
      return false;
    }

    final model = await _getRaspberryPiModel(readFile: readFile);
    if (model != null) {
      return true;
    }

    return true;
  }

  static Future<bool> _isRaspberryPi5({
    Future<String?> Function(String path)? readFile,
  }) async {
    final model = await _getRaspberryPiModel(readFile: readFile);
    return model != null && model.contains('raspberry pi 5');
  }

  static Future<bool> _isRaspberryPi4({
    Future<String?> Function(String path)? readFile,
  }) async {
    final model = await _getRaspberryPiModel(readFile: readFile);
    return model != null && model.contains('raspberry pi 4');
  }

  static Future<bool> _isRaspberryPi3({
    Future<String?> Function(String path)? readFile,
  }) async {
    final model = await _getRaspberryPiModel(readFile: readFile);
    return model != null && model.contains('raspberry pi 3');
  }

  static Future<String?> _getRaspberryPiModel({
    Future<String?> Function(String path)? readFile,
  }) async {
    if (!Platform.isLinux) {
      return null;
    }

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
      final normalized = content.toLowerCase();
      if (normalized.contains('raspberry')) {
        return normalized;
      }
      if (path.contains('cpuinfo') &&
          (normalized.contains('bcm') || normalized.contains('raspberry'))) {
        return normalized;
      }
    }

    return null;
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
