/// Identifiers for dashboard / control-plane clients vs normal user devices.
class DashboardClientIds {
  DashboardClientIds._();

  static const String dashboardAdminDeviceId = 'desktop_dashboard_admin';
  static const String dashboardAdminDeviceName = 'Ariami Desktop Dashboard';
  static const String cliWebDashboardDeviceName = 'Ariami CLI Web Dashboard';

  static const String clientTypeDashboard = 'dashboard';
  static const String clientTypeUserDevice = 'user_device';
  static const String clientTypeUnauthenticated = 'unauthenticated';
}

/// One row in the connected users/devices table.
class ConnectedClientRow {
  const ConnectedClientRow({
    required this.deviceId,
    required this.deviceName,
    required this.clientType,
    required this.connectedAt,
    required this.lastHeartbeat,
    this.userId,
    this.username,
  });

  final String deviceId;
  final String deviceName;
  final String clientType;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;
  final String? userId;
  final String? username;
}

/// Helpers for resolving client types and display labels.
class ConnectedClientFormatting {
  ConnectedClientFormatting._();

  static bool isDashboardControlClient({
    required String deviceId,
    required String deviceName,
  }) {
    return deviceId == DashboardClientIds.dashboardAdminDeviceId ||
        deviceName == DashboardClientIds.dashboardAdminDeviceName ||
        deviceName == DashboardClientIds.cliWebDashboardDeviceName;
  }

  static String resolveConnectedClientType({
    required String deviceId,
    required String deviceName,
    required String? userId,
  }) {
    if (isDashboardControlClient(
        deviceId: deviceId, deviceName: deviceName)) {
      return DashboardClientIds.clientTypeDashboard;
    }
    if (userId == null) {
      return DashboardClientIds.clientTypeUnauthenticated;
    }
    return DashboardClientIds.clientTypeUserDevice;
  }

  static String formatConnectedDeviceLabel(ConnectedClientRow row) {
    if (row.clientType == DashboardClientIds.clientTypeDashboard) {
      return '${row.deviceName} (Dashboard)';
    }
    return row.deviceName;
  }
}
