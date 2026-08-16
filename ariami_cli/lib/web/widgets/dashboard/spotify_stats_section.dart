import 'package:ariami_core/models/listening_stats_models.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../ui/info_row.dart';
import '../ui/section.dart';

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
    final hasImport = status?.hasImport ?? false;

    return Section(
      title: 'Listening history',
      description: 'Bring your Spotify history in so Ariami can build on it.',
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            InfoRow(
              icon: Icons.history_rounded,
              label: 'Imported plays',
              isActive: hasImport,
              value: status == null
                  ? 'Checking…'
                  : hasImport
                      ? '${formatPlayCount(status.plays)} '
                          '${status.plays == 1 ? 'play' : 'plays'}'
                      : 'None imported',
              subtitle: status != null && hasImport
                  ? 'Covering ${formatStatsDate(status.oldestPlayAtMs)} – '
                      '${formatStatsDate(status.newestPlayAtMs)} · '
                      'last import ${formatStatsDateTime(status.lastImportedAtMs)}'
                  : null,
            ),
            const CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: onImportSpotifyStats,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Import Spotify history'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        status != null && !hasImport ? null : onRemoveSpotifyStats,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove import'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: BorderSide(
                        color: AppTheme.danger.withValues(alpha: 0.45),
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
