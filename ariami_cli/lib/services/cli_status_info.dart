import 'dart:convert';
import 'dart:io';

import 'cli_state_service.dart';

/// Offline summary of the local auth store, read directly from users.json.
///
/// Used for startup banners and `status` output in processes that have not
/// initialized the full AuthService (e.g. the CLI front process while the
/// daemon owns the server). Never exposes password hashes or session data.
class AuthSummary {
  const AuthSummary({required this.accountCount, required this.readable});

  /// Number of registered accounts (0 when the file is missing or unreadable).
  final int accountCount;

  /// False when users.json exists but could not be parsed.
  final bool readable;

  /// The first created account is the owner/admin, so any account implies one.
  bool get hasOwnerAccount => accountCount > 0;
}

/// Read account information from the CLI's users.json without AuthService.
Future<AuthSummary> readAuthSummary() async {
  final file = File(CliStateService.getUsersFilePath());
  if (!await file.exists()) {
    return const AuthSummary(accountCount: 0, readable: true);
  }

  try {
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const AuthSummary(accountCount: 0, readable: true);
    }
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      final users = decoded['users'];
      if (users is List) {
        return AuthSummary(accountCount: users.length, readable: true);
      }
    }
    return const AuthSummary(accountCount: 0, readable: false);
  } catch (_) {
    return const AuthSummary(accountCount: 0, readable: false);
  }
}
