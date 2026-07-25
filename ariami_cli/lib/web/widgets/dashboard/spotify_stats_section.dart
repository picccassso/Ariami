import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// The signed-in account's Spotify import: what it currently holds, plus the
/// actions that change it.
class SpotifyStatsSection extends StatelessWidget {
  const SpotifyStatsSection({
    super.key,
    required this.importStatus,
    required this.onImportSpotifyStats,
    required this.onRemoveSpotifyStats,
  });

  /// Null while the status is still unknown — either not loaded yet or the
  /// request failed. Removal stays available in that case rather than
  /// stranding the action behind a failed read.
  final SpotifyImportStatus? importStatus;

  final VoidCallback onImportSpotifyStats;
  final VoidCallback onRemoveSpotifyStats;

  @override
  Widget build(BuildContext context) {
    final status = importStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LISTENING STATISTICS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          status == null
              ? 'Checking for an imported Spotify history…'
              : status.hasImport
                  ? '${formatPlayCount(status.plays)} imported '
                      '${status.plays == 1 ? 'play' : 'plays'} · last import '
                      '${formatStatsDateTime(status.lastImportedAtMs)}'
                  : 'No Spotify plays imported.',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        if (status != null && status.hasImport) ...[
          const SizedBox(height: 4),
          Text(
            'Covering ${formatStatsDate(status.oldestPlayAtMs)} – '
            '${formatStatsDate(status.newestPlayAtMs)}',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: onImportSpotifyStats,
                icon: const Icon(Icons.history_rounded),
                label: const Text('IMPORT SPOTIFY STATS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceBlack,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.borderGrey),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: status != null && !status.hasImport
                    ? null
                    : onRemoveSpotifyStats,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('REMOVE SPOTIFY STATS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceBlack,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.borderGrey),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `1234567` → `1,234,567`, so six-figure imports stay readable.
String formatPlayCount(int plays) {
  final digits = plays.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Local `d/m/yyyy`; em dash when the timestamp is missing.
String formatStatsDate(int? millis) {
  if (millis == null) return '—';
  final local = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${local.day}/${local.month}/${local.year}';
}

/// Local `d/m/yyyy hh:mm`; em dash when the timestamp is missing.
String formatStatsDateTime(int? millis) {
  if (millis == null) return '—';
  final local = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${formatStatsDate(millis)} '
      '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
}
