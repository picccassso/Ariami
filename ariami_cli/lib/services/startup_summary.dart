/// Formats the Ariami server startup summary.
class StartupSummary {
  static const _line =
      '──────────────────────────────────────────────────────────';

  /// Build the startup banner as printable lines.
  static List<String> buildBanner({
    required String version,
    required String modeLabel,
    required int port,
    required String bindHost,
    required String? lanIp,
    required String? tailscaleIp,
    required String dataDir,
    required String? musicDir,
    required bool musicDirExists,
    required int accountCount,
    required bool hasOwnerAccount,
    required bool setupComplete,
    int? pid,
  }) {
    final isLocalOnly = _isLocalOnly(bindHost);
    final lines = <String>[
      _line,
      ' Ariami Server $version',
      ' Status:    ${_statusText(
        modeLabel: modeLabel,
        setupComplete: setupComplete,
        pid: pid,
      )}',
    ];

    if (!isLocalOnly && lanIp != null) {
      lines.add(' Dashboard: http://$lanIp:$port');
    }

    lines.add(' Local:     http://127.0.0.1:$port');

    if (!isLocalOnly && tailscaleIp != null) {
      lines.add(' Tailscale: http://$tailscaleIp:$port');
    }

    if (isLocalOnly) {
      lines.add(
        ' Note:      bound to localhost only — other devices cannot connect.',
      );
    }

    lines.add(' Data:      $dataDir');
    lines.add(' Music:     ${_musicText(musicDir, musicDirExists)}');
    lines.add(' Auth:      ${_authText(accountCount, hasOwnerAccount)}');

    if (!setupComplete) {
      lines.add(
          ' Setup:     required — open the Dashboard URL above to continue');
    }

    lines.add(
      ' Network:   LAN/Tailscale/VPN only. Do not expose this port to the public internet.',
    );
    lines.add(_line);

    return lines;
  }

  static String _statusText({
    required String modeLabel,
    required bool setupComplete,
    required int? pid,
  }) {
    if (!setupComplete) {
      return 'setup required — finish setup in the browser';
    }

    if (modeLabel.toLowerCase() == 'background' && pid != null) {
      return 'running (background, PID $pid)';
    }

    return 'running (foreground)';
  }

  static String _musicText(String? musicDir, bool musicDirExists) {
    if (musicDir == null || musicDir.isEmpty) {
      return 'not configured — choose it in the dashboard';
    }

    if (!musicDirExists) {
      return '$musicDir (folder missing!)';
    }

    return musicDir;
  }

  static String _authText(int accountCount, bool hasOwnerAccount) {
    if (!hasOwnerAccount || accountCount == 0) {
      return 'enabled — no owner account yet. Create one in the dashboard before real use.';
    }

    final suffix = accountCount == 1 ? 'account' : 'accounts';
    return 'enabled — $accountCount $suffix';
  }

  static bool _isLocalOnly(String bindHost) {
    final normalized = bindHost.trim().toLowerCase();
    return normalized == '127.0.0.1' || normalized == 'localhost';
  }
}
