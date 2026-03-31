import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'stat_card.dart';

class LibraryStatsSection extends StatelessWidget {
  const LibraryStatsSection({
    super.key,
    required this.songCount,
    required this.albumCount,
    required this.connectedClients,
    required this.connectedUsers,
    required this.activeSessions,
    required this.lastScanTimeFormatted,
  });

  final int songCount;
  final int albumCount;
  final int connectedClients;
  final int connectedUsers;
  final int activeSessions;
  final String lastScanTimeFormatted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LIBRARY STATISTICS',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'LAST SCAN: ${lastScanTimeFormatted.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 3 : 1,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.2,
          children: [
            StatCard(
              icon: Icons.music_note_rounded,
              count: '$songCount',
              label: 'SONGS FOUND',
            ),
            StatCard(
              icon: Icons.album_rounded,
              count: '$albumCount',
              label: 'ALBUMS INDEXED',
            ),
            StatCard(
              icon: Icons.devices_rounded,
              count: '$connectedClients',
              label: 'ACTIVE CLIENTS',
            ),
            StatCard(
              icon: Icons.people_rounded,
              count: '$connectedUsers',
              label: 'CONNECTED USERS',
            ),
            StatCard(
              icon: Icons.vpn_key_rounded,
              count: '$activeSessions',
              label: 'ACTIVE SESSIONS',
            ),
          ],
        ),
      ],
    );
  }
}
