import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../endpoint_display.dart';

class ServerInfoCard extends StatelessWidget {
  const ServerInfoCard({
    super.key,
    this.lanServer,
    this.tailscaleServer,
  });

  final String? lanServer;
  final String? tailscaleServer;

  @override
  Widget build(BuildContext context) {
    final hasEndpoints =
        (lanServer != null && lanServer!.isNotEmpty) ||
            (tailscaleServer != null && tailscaleServer!.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 24, color: Colors.white),
              const SizedBox(width: 16),
              Text(
                'SERVER INFO',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (hasEndpoints) ...[
            const Text(
              'AVAILABLE ENDPOINTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            if (lanServer != null && lanServer!.isNotEmpty) ...[
              EndpointDisplay(
                label: 'Local Network',
                value: lanServer!,
                badgeLabel: 'LAN',
              ),
              if (tailscaleServer != null && tailscaleServer!.isNotEmpty)
                const SizedBox(height: 16),
            ],
            if (tailscaleServer != null && tailscaleServer!.isNotEmpty)
              EndpointDisplay(
                label: 'Tailscale',
                value: tailscaleServer!,
                badgeLabel: 'REMOTE',
              ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white10),
            const SizedBox(height: 20),
          ],
          const Text(
            'The Ariami server is broadcasting securely. Mobile clients can connect via your local network or Tailscale address.',
            style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
                height: 1.6),
          ),
          const SizedBox(height: 12),
          const Text(
            'For the best experience, ensure your mobile device is on the same network or has Tailscale enabled.',
            style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
                height: 1.6),
          ),
        ],
      ),
    );
  }
}
