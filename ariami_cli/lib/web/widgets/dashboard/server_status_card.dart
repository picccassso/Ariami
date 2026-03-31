import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class ServerStatusCard extends StatelessWidget {
  const ServerStatusCard({
    super.key,
    required this.serverRunning,
    required this.isScanning,
    required this.pulseController,
  });

  final bool serverRunning;
  final bool isScanning;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glassDecoration,
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          FadeTransition(
            opacity: pulseController,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: serverRunning ? Colors.white : Colors.redAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (serverRunning ? Colors.white : Colors.redAccent)
                        .withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SERVER STATUS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                serverRunning ? 'ACTIVE & STREAMING' : 'SERVER STOPPED',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: serverRunning ? Colors.white : Colors.redAccent,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (isScanning)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'SCANNING...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
