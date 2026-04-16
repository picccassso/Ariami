/// One row in the registered users table.
class ServerUserRow {
  const ServerUserRow({
    required this.userId,
    required this.username,
    required this.createdAt,
    required this.isAdmin,
    required this.connectedDeviceCount,
  });

  final String userId;
  final String username;
  final DateTime? createdAt;
  final bool isAdmin;
  final int connectedDeviceCount;
}
