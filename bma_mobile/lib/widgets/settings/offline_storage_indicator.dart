import 'package:flutter/material.dart';
import '../../services/download/download_manager.dart';

/// Widget that displays offline storage usage and downloaded song count
class OfflineStorageIndicator extends StatelessWidget {
  final VoidCallback? onManageDownloads;

  const OfflineStorageIndicator({
    super.key,
    this.onManageDownloads,
  });

  @override
  Widget build(BuildContext context) {
    final downloadManager = DownloadManager();
    final totalSizeMB = downloadManager.getTotalDownloadedSizeMB();
    final downloadCount = downloadManager.getCompletedDownloadCount();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Offline Storage',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Storage used
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.storage,
                    label: 'Storage Used',
                    value: _formatStorageSize(totalSizeMB),
                  ),
                ),
                // Songs downloaded
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.music_note,
                    label: 'Songs',
                    value: downloadCount.toString(),
                  ),
                ),
              ],
            ),
            if (onManageDownloads != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onManageDownloads,
                  icon: const Icon(Icons.settings),
                  label: const Text('Manage Downloads'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Format storage size for display
  String _formatStorageSize(double sizeMB) {
    if (sizeMB < 0.01) {
      return '0 MB';
    } else if (sizeMB < 1000) {
      return '${sizeMB.toStringAsFixed(1)} MB';
    } else {
      final sizeGB = sizeMB / 1024;
      return '${sizeGB.toStringAsFixed(2)} GB';
    }
  }
}





