import 'package:ariami_core/models/music_availability.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/layout.dart';
import '../ui/status_pill.dart';

/// Headline state of the server, plus the addresses people connect to.
class ServerStatusCard extends StatelessWidget {
  const ServerStatusCard({
    super.key,
    required this.serverRunning,
    this.musicAvailability = MusicAvailability.unknown,
    required this.isScanning,
    required this.pulseController,
    this.lanServer,
    this.lanServerAlias,
    this.tailscaleServer,
    this.tailscaleServerAlias,
  });

  final bool serverRunning;
  final MusicAvailability musicAvailability;
  final bool isScanning;
  final AnimationController pulseController;
  final String? lanServer;
  final String? lanServerAlias;
  final String? tailscaleServer;
  final String? tailscaleServerAlias;

  @override
  Widget build(BuildContext context) {
    final isCompact = AppLayout.of(context) == WidthClass.compact;
    final reachableAt = [
      if (lanServer != null && lanServer!.isNotEmpty)
        (lanServerAlias != null && lanServerAlias!.trim().isNotEmpty)
            ? lanServerAlias!
            : lanServer!,
      if (tailscaleServer != null && tailscaleServer!.isNotEmpty)
        (tailscaleServerAlias != null &&
                tailscaleServerAlias!.trim().isNotEmpty)
            ? tailscaleServerAlias!
            : tailscaleServer!,
    ];

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          serverRunning ? musicAvailability.title : 'Server stopped',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          serverRunning
              ? musicAvailability.needsAttention
                  ? musicAvailability.message
                  : reachableAt.isEmpty
                      ? 'Sign in from the Ariami app on your phone, TV or desktop.'
                      : 'Reachable at ${reachableAt.join('  ·  ')}'
              : 'Start Ariami on this machine to stream again.',
          style: AppTheme.meta.copyWith(fontSize: 13.5),
        ),
      ],
    );

    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusPill(
          label: serverRunning ? 'Running' : 'Stopped',
          tone: serverRunning ? StatusTone.positive : StatusTone.negative,
          pulse: serverRunning ? pulseController : null,
        ),
        if (serverRunning && musicAvailability.needsAttention)
          const StatusPill(
              label: 'Music needs attention', tone: StatusTone.caution),
        if (isScanning)
          const StatusPill(
            label: 'Scanning library',
            tone: StatusTone.neutral,
            busy: true,
          ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: AppTheme.cardDecoration(),
      padding: EdgeInsets.all(isCompact ? 20 : 24),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [pills, const SizedBox(height: 16), heading],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 20),
                pills,
              ],
            ),
    );
  }
}
