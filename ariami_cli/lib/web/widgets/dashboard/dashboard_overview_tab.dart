import 'package:flutter/material.dart';

import 'auth_required_banner.dart';
import 'dashboard_keep_alive_tab.dart';
import 'library_stats_section.dart';
import 'quick_actions_section.dart';
import 'server_status_card.dart';

class DashboardOverviewTab extends StatelessWidget {
  const DashboardOverviewTab({
    super.key,
    required this.serverRunning,
    required this.isScanning,
    required this.pulseController,
    required this.authRequired,
    required this.songCount,
    required this.albumCount,
    required this.connectedClients,
    required this.connectedUsers,
    required this.activeSessions,
    required this.lastScanTimeFormatted,
    required this.onRescanLibrary,
    required this.onViewQRCode,
  });

  final bool serverRunning;
  final bool isScanning;
  final AnimationController pulseController;
  final bool authRequired;
  final int songCount;
  final int albumCount;
  final int connectedClients;
  final int connectedUsers;
  final int activeSessions;
  final String lastScanTimeFormatted;
  final VoidCallback onRescanLibrary;
  final VoidCallback onViewQRCode;

  @override
  Widget build(BuildContext context) {
    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServerStatusCard(
            serverRunning: serverRunning,
            isScanning: isScanning,
            pulseController: pulseController,
          ),
          const SizedBox(height: 24),
          if (authRequired) const AuthRequiredBanner(),
          LibraryStatsSection(
            songCount: songCount,
            albumCount: albumCount,
            connectedClients: connectedClients,
            connectedUsers: connectedUsers,
            activeSessions: activeSessions,
            lastScanTimeFormatted: lastScanTimeFormatted,
          ),
          const SizedBox(height: 48),
          QuickActionsSection(
            isScanning: isScanning,
            onRescanLibrary: onRescanLibrary,
            onViewQRCode: onViewQRCode,
          ),
        ],
      ),
    );
  }
}
