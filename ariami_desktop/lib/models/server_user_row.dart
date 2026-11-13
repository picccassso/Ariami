import 'package:ariami_core/models/library_curation.dart';

/// One row in the registered users table.
class ServerUserRow {
  const ServerUserRow({
    required this.userId,
    required this.username,
    required this.createdAt,
    required this.isAdmin,
    required this.connectedDeviceCount,
    this.curationSummary,
  });

  final String userId;
  final String username;
  final DateTime? createdAt;
  final bool isAdmin;
  final int connectedDeviceCount;
  final Map<String, dynamic>? curationSummary;

  String get librarySummaryLabel =>
      UserLibraryCuration.formatSummaryLabel(curationSummary);
}
