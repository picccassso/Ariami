import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

import '../../utils/date_formatter.dart';
import '../info_card.dart';
import 'dashboard_keep_alive_tab.dart';

class DashboardOverviewTab extends StatelessWidget {
  const DashboardOverviewTab({
    super.key,
    required this.httpServer,
    required this.connectedClients,
    required this.hasOwnerAccount,
    required this.onToggleServer,
    required this.onOpenOwnerSetup,
  });

  final AriamiHttpServer httpServer;
  final int connectedClients;
  final bool hasOwnerAccount;
  final VoidCallback onToggleServer;
  final VoidCallback onOpenOwnerSetup;

  static const _sectionTitleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  @override
  Widget build(BuildContext context) {
    final isRunning = httpServer.isRunning;

    return DashboardKeepAliveTab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Server Status', style: _sectionTitleStyle),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Status',
            value: isRunning ? 'Active' : 'Stopped',
            icon: isRunning
                ? Icons.check_circle_rounded
                : Icons.stop_circle_rounded,
            isActive: isRunning,
          ),
          const SizedBox(height: 12),
          if (isRunning) ...[
            InfoCard(
              title: 'Connected Clients',
              value: connectedClients.toString(),
              icon: Icons.devices_rounded,
              isActive: connectedClients > 0,
            ),
            const SizedBox(height: 12),
            InfoCard(
              title: 'Connected Users',
              value: httpServer.connectedUsers.toString(),
              icon: Icons.people_rounded,
              isActive: httpServer.connectedUsers > 0,
            ),
            const SizedBox(height: 12),
            InfoCard(
              title: 'Active Sessions',
              value: httpServer.activeSessions.toString(),
              icon: Icons.vpn_key_rounded,
              isActive: httpServer.activeSessions > 0,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onToggleServer,
              icon: Icon(
                isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(isRunning ? 'Stop Server' : 'Start Server'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor:
                    isRunning ? const Color(0xFF141414) : Colors.white,
                foregroundColor: isRunning ? Colors.redAccent : Colors.black,
                side: isRunning
                    ? const BorderSide(color: Colors.redAccent, width: 2)
                    : null,
                elevation: isRunning ? 0 : 2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!hasOwnerAccount)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_add_alt_1_rounded,
                          color: Colors.orange.shade300, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Owner setup is pending. Owner is the first account created on this server.',
                          style: TextStyle(
                            color: Colors.orange.shade200,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onOpenOwnerSetup,
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Set Up Owner Account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade100,
                      side: BorderSide(color: Colors.orange.shade400),
                    ),
                  ),
                ],
              ),
            )
          else if (httpServer.authRequired)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded,
                      color: Colors.orange.shade300, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Owner authentication is enabled. Users must sign in to access this server.',
                      style: TextStyle(
                        color: Colors.orange.shade200,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const Text('Library Statistics', style: _sectionTitleStyle),
          const SizedBox(height: 16),
          InfoCard(
            title: 'Albums',
            value: httpServer.libraryManager.library?.totalAlbums.toString() ??
                '0',
            icon: Icons.album_rounded,
            isActive:
                (httpServer.libraryManager.library?.totalAlbums ?? 0) > 0,
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Songs',
            value:
                httpServer.libraryManager.library?.totalSongs.toString() ?? '0',
            icon: Icons.music_note_rounded,
            isActive: (httpServer.libraryManager.library?.totalSongs ?? 0) > 0,
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Last Scan',
            value: httpServer.libraryManager.lastScanTime != null
                ? formatDashboardDateTime(
                    httpServer.libraryManager.lastScanTime!)
                : 'Never',
            icon: Icons.access_time_rounded,
            isActive: httpServer.libraryManager.lastScanTime != null,
          ),
        ],
      ),
    );
  }
}
