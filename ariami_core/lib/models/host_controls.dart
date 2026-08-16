/// Host-level server controls exposed to the web dashboard.
///
/// These are settings that belong to the machine running the server rather
/// than to the library or to an account: where the music lives, whether the
/// server comes back after a reboot, and whether this host can reset itself.
///
/// Only hosts that register host-control callbacks (currently the CLI) answer
/// these endpoints. Ariami Desktop manages the same settings in-process and
/// leaves the callbacks unset, so the routes report "not configured" there.
class HostControlsSnapshot {
  const HostControlsSnapshot({
    this.musicFolderPath,
    this.autostartSupported = false,
    this.autostartEnabled = false,
    this.resetSupported = false,
  });

  /// Configured music library path, or null when setup has not chosen one.
  final String? musicFolderPath;

  /// Whether this host can start the server at boot at all. False on
  /// platforms with no supported mechanism (e.g. inside a container).
  final bool autostartSupported;

  /// Whether start-at-boot is currently enabled.
  final bool autostartEnabled;

  /// Whether this host can reset its own Ariami data.
  final bool resetSupported;

  Map<String, dynamic> toJson() => {
        'musicFolderPath': musicFolderPath,
        'autostartSupported': autostartSupported,
        'autostartEnabled': autostartEnabled,
        'resetSupported': resetSupported,
      };

  factory HostControlsSnapshot.fromJson(Map<String, dynamic> json) {
    return HostControlsSnapshot(
      musicFolderPath: json['musicFolderPath'] as String?,
      autostartSupported: json['autostartSupported'] as bool? ?? false,
      autostartEnabled: json['autostartEnabled'] as bool? ?? false,
      resetSupported: json['resetSupported'] as bool? ?? false,
    );
  }
}

/// Outcome of a host reset requested from the dashboard.
class HostResetOutcome {
  const HostResetOutcome({
    required this.success,
    required this.message,
    this.failedPaths = const <String>[],
  });

  final bool success;

  /// Human-readable summary shown in the dashboard.
  final String message;

  /// Paths the reset could not remove, if any.
  final List<String> failedPaths;

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'failedPaths': failedPaths,
      };

  factory HostResetOutcome.fromJson(Map<String, dynamic> json) {
    return HostResetOutcome(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      failedPaths: (json['failedPaths'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
