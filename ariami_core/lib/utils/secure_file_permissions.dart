import 'dart:io';

/// Best-effort permission hardening for files and directories that hold
/// auth secrets (users.json, sessions.json and their parent directory).
///
/// Dart has no portable chmod API, so this shells out to `chmod` on Unix
/// platforms and is a no-op on Windows (where per-user profile ACLs already
/// scope access to the owner). Failures are swallowed: permissions are a
/// hardening layer and must never take the server down.
class SecureFilePermissions {
  SecureFilePermissions._();

  /// Owner-only read/write (0600) on a file.
  static Future<void> restrictFile(String path) => _chmod('600', path);

  /// Owner-only access (0700) on a directory.
  static Future<void> restrictDirectory(String path) => _chmod('700', path);

  static Future<void> _chmod(String mode, String path) async {
    if (Platform.isWindows) {
      return;
    }
    try {
      await Process.run('chmod', [mode, path]);
    } catch (_) {
      // Best effort only.
    }
  }
}
