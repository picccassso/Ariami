import 'dart:io';

import '../../utils/device_model.dart';

class TranscodeSlotsSnapshot {
  const TranscodeSlotsSnapshot({
    required this.effective,
    required this.defaultSlots,
    this.override,
    this.restartRequired = true,
  });

  /// Active slot count (override when set, otherwise [defaultSlots]).
  final int effective;

  final int defaultSlots;

  final int? override;

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

    final onPi = isRaspberryPi ?? DeviceModel.isRaspberryPi();
    if (onPi) {
      final onPi5 = isRaspberryPi5 ??
          await DeviceModel.isRaspberryPiGeneration(5, readFile: readFile);
      if (onPi5) {
        return 5;
      }
      final onPi4 = isRaspberryPi4 ??
          await DeviceModel.isRaspberryPiGeneration(4, readFile: readFile);
      if (onPi4) {
        return 4;
      }
      final onPi3 = isRaspberryPi3 ??
          await DeviceModel.isRaspberryPiGeneration(3, readFile: readFile);
      if (onPi3) {
        return 3;
      }
      // Unrecognised / older Pi: use the most conservative supported default.
      return 3;
    }

    return desktopDefaultSlots;
  }

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

  static void validateSlots(int slots) {
    if (slots < minSlots) {
      throw ArgumentError.value(
        slots,
        'slots',
        'must be an integer >= $minSlots',
      );
    }
  }
}
