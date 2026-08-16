import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../ui/info_row.dart';
import '../ui/section.dart';

/// Where clients reach this server, and when those addresses were last read.
class ServerConnectionSection extends StatelessWidget {
  const ServerConnectionSection({
    super.key,
    this.lanServer,
    this.tailscaleServer,
    this.lastUpdatedLabel,
    required this.isRefreshing,
    required this.onRefreshAddresses,
  });

  final String? lanServer;
  final String? tailscaleServer;
  final String? lastUpdatedLabel;
  final bool isRefreshing;
  final VoidCallback onRefreshAddresses;

  @override
  Widget build(BuildContext context) {
    final lan = lanServer;
    final tailscale = tailscaleServer;

    return Section(
      title: 'Connection',
      description: 'Keep Ariami on your LAN, Tailscale or VPN — never expose '
          'it directly to the internet.',
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            InfoRow(
              icon: Icons.router_rounded,
              label: 'Local network',
              value: lan != null && lan.isNotEmpty ? lan : 'Not connected',
              subtitle: 'For devices on the same Wi-Fi or wired network.',
              isActive: lan != null && lan.isNotEmpty,
              valueIsPath: lan != null && lan.isNotEmpty,
            ),
            const CardDivider(),
            InfoRow(
              icon: Icons.cloud_done_rounded,
              label: 'Tailscale',
              value: tailscale != null && tailscale.isNotEmpty
                  ? tailscale
                  : 'Not connected',
              subtitle: tailscale != null && tailscale.isNotEmpty
                  ? 'For your signed-in devices when away from home.'
                  : 'Optional. Install Tailscale to reach Ariami away from '
                      'home.',
              isActive: tailscale != null && tailscale.isNotEmpty,
              valueIsPath: tailscale != null && tailscale.isNotEmpty,
            ),
            const CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lastUpdatedLabel == null
                          ? 'Addresses are re-read automatically.'
                          : 'Addresses updated $lastUpdatedLabel',
                      style: AppTheme.meta,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: isRefreshing ? null : onRefreshAddresses,
                    icon: isRefreshing
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(isRefreshing ? 'Refreshing…' : 'Refresh'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
