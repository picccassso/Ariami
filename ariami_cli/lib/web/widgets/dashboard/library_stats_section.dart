import 'package:flutter/material.dart';

import '../../utils/layout.dart';
import '../ui/section.dart';
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
    required this.isScanning,
    required this.onRescanLibrary,
  });

  final int songCount;
  final int albumCount;
  final int connectedClients;
  final int connectedUsers;
  final int activeSessions;
  final String lastScanTimeFormatted;
  final bool isScanning;
  final VoidCallback onRescanLibrary;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      StatCard(
        icon: Icons.music_note_rounded,
        count: '$songCount',
        label: 'Songs',
      ),
      StatCard(
        icon: Icons.album_rounded,
        count: '$albumCount',
        label: 'Albums',
      ),
      StatCard(
        icon: Icons.devices_rounded,
        count: '$connectedClients',
        label: 'Connected devices',
      ),
      StatCard(
        icon: Icons.people_rounded,
        count: '$connectedUsers',
        label: 'Connected users',
      ),
      StatCard(
        icon: Icons.vpn_key_rounded,
        count: '$activeSessions',
        label: 'Active sessions',
      ),
    ];

    return Section(
      title: 'Library',
      description: 'Last scan: $lastScanTimeFormatted',
      trailing: TextButton.icon(
        onPressed: isScanning ? null : onRescanLibrary,
        icon: isScanning
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 17),
        label: Text(isScanning ? 'Scanning…' : 'Rescan'),
      ),
      child: _StatGrid(tiles: tiles),
    );
  }
}

/// Flows tiles into 1–3 columns, sizing each row to fill the width.
///
/// Two things this fixes: the previous `GridView.count(childAspectRatio: 2.2)`
/// tied tile height to column width, so on a wide monitor each tile grew to
/// nearly 300px tall around a single number; and with five tiles in three
/// columns the last row left a visible hole, so a short final row shares the
/// full width instead.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<Widget> tiles;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = AppLayout.statColumnsForContentWidth(width);

        final rows = <List<Widget>>[];
        for (var i = 0; i < tiles.length; i += columns) {
          rows.add(tiles.sublist(i, (i + columns).clamp(0, tiles.length)));
        }

        return Column(
          children: [
            for (final row in rows) ...[
              // IntrinsicHeight so tiles in a row match the tallest one.
              // `CrossAxisAlignment.stretch` alone cannot do it here: the
              // grid sits in a scroll view, so the Row's cross axis is
              // unbounded and stretching collapses the whole section.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final tile in row) ...[
                      Expanded(child: tile),
                      if (tile != row.last) const SizedBox(width: _gap),
                    ],
                  ],
                ),
              ),
              if (row != rows.last) const SizedBox(height: _gap),
            ],
          ],
        );
      },
    );
  }
}
