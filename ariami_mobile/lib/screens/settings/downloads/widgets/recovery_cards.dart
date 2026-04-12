import 'package:flutter/material.dart';

class DownloadsInterruptionRecoveryCard extends StatelessWidget {
  const DownloadsInterruptionRecoveryCard({
    super.key,
    required this.isDark,
    required this.interruptedDownloadCount,
    required this.onResumeAll,
    required this.onCancelAll,
  });

  final bool isDark;
  final int interruptedDownloadCount;
  final VoidCallback onResumeAll;
  final VoidCallback onCancelAll;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 10),
                Text(
                  'Interrupted Downloads',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$interruptedDownloadCount download${interruptedDownloadCount == 1 ? '' : 's'} paused after connection loss.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[500] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onResumeAll,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Resume All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFF5F5F5),
                      foregroundColor: isDark ? Colors.white : Colors.black,
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCancelAll,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Cancel Remaining'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFF5F5F5),
                      foregroundColor: const Color(0xFFFF4B4B),
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadsRecoveryPreferencesCard extends StatelessWidget {
  const DownloadsRecoveryPreferencesCard({
    super.key,
    required this.isDark,
    required this.autoResumeOnLaunch,
    required this.onChanged,
  });

  final bool isDark;
  final bool autoResumeOnLaunch;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.autorenew_rounded,
              size: 20,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-Resume On Launch',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    autoResumeOnLaunch
                        ? 'Interrupted downloads resume automatically when the app reopens.'
                        : 'Show a prompt to continue or keep paused when reopening the app.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: autoResumeOnLaunch,
              onChanged: onChanged,
              activeThumbColor: isDark ? Colors.white : Colors.black,
            ),
          ],
        ),
      ),
    );
  }
}
