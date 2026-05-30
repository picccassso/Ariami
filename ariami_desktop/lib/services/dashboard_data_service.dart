import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';

import '../models/connected_client_row.dart';
import '../models/server_user_row.dart';
import 'desktop_state_service.dart';

/// Builds the dashboard's read-only user, client, and activity snapshots.
class DashboardDataService {
  const DashboardDataService({
    required this.httpServer,
    required this.stateService,
  });

  final AriamiHttpServer httpServer;
  final DesktopStateService stateService;

  Future<List<ServerUserRow>> loadServerUsers() async {
    final users = await _loadStoredUsers();
    final connectedDeviceCountByUserId = <String, int>{};
    for (final client in httpServer.connectionManager.getConnectedClients()) {
      final userId = client.userId;
      if (userId == null || userId.isEmpty) continue;
      if (ConnectedClientFormatting.isDashboardControlClient(
        deviceId: client.deviceId,
        deviceName: client.deviceName,
      )) {
        continue;
      }
      connectedDeviceCountByUserId[userId] =
          (connectedDeviceCountByUserId[userId] ?? 0) + 1;
    }

    final adminUserId = users.isEmpty ? null : users.first.userId;
    return users
        .map(
          (user) => ServerUserRow(
            userId: user.userId,
            username: user.username,
            createdAt: user.createdAt,
            isAdmin: adminUserId == user.userId,
            connectedDeviceCount:
                connectedDeviceCountByUserId[user.userId] ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ConnectedClientRow>> loadConnectedClients() async {
    final usernameById = await _loadUsernameMap();
    final rows = httpServer.connectionManager
        .getConnectedClients()
        .map(
          (client) => ConnectedClientRow(
            deviceId: client.deviceId,
            deviceName: client.deviceName,
            clientType: ConnectedClientFormatting.resolveConnectedClientType(
              deviceId: client.deviceId,
              deviceName: client.deviceName,
              userId: client.userId,
            ),
            userId: client.userId,
            username: client.userId == null
                ? null
                : usernameById[client.userId!] ?? client.userId!,
            connectedAt: client.connectedAt,
            lastHeartbeat: client.lastHeartbeat,
          ),
        )
        .toList()
      ..sort((a, b) => b.lastHeartbeat.compareTo(a.lastHeartbeat));
    return rows;
  }

  List<UserActivityRow> loadUserActivity() {
    if (!httpServer.isRunning) {
      return const <UserActivityRow>[];
    }
    return httpServer.getActiveUserActivityRows();
  }

  Future<Map<String, String>> _loadUsernameMap() async {
    try {
      final users = await _loadStoredUsers();
      return <String, String>{
        for (final user in users) user.userId: user.username,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<List<_StoredDashboardUser>> _loadStoredUsers() async {
    final usersPath = await stateService.getUsersFilePath();
    final usersFile = File(usersPath);
    if (!await usersFile.exists()) return const <_StoredDashboardUser>[];

    final raw = await usersFile.readAsString();
    if (raw.trim().isEmpty) return const <_StoredDashboardUser>[];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <_StoredDashboardUser>[];
    }
    final users = decoded['users'];
    if (users is! List) return const <_StoredDashboardUser>[];

    final parsed = <_StoredDashboardUser>[];
    for (final userEntry in users) {
      if (userEntry is! Map) continue;
      final userId = userEntry['userId']?.toString().trim();
      if (userId == null || userId.isEmpty) continue;

      final username = userEntry['username']?.toString().trim();
      final createdAtRaw = userEntry['createdAt']?.toString() ?? '';
      parsed.add(
        _StoredDashboardUser(
          userId: userId,
          username: (username == null || username.isEmpty)
              ? 'Unknown User'
              : username,
          createdAt: DateTime.tryParse(createdAtRaw),
          createdAtRaw: createdAtRaw,
        ),
      );
    }

    parsed.sort((a, b) {
      final createdCompare = a.createdAtRaw.compareTo(b.createdAtRaw);
      if (createdCompare != 0) return createdCompare;
      return a.userId.compareTo(b.userId);
    });
    return parsed;
  }
}

class _StoredDashboardUser {
  const _StoredDashboardUser({
    required this.userId,
    required this.username,
    required this.createdAt,
    required this.createdAtRaw,
  });

  final String userId;
  final String username;
  final DateTime? createdAt;
  final String createdAtRaw;
}
