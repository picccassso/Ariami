import 'package:flutter/material.dart';

class DownloadModeCard extends StatelessWidget {
  const DownloadModeCard({
    super.key,
    required this.isDark,
    required this.downloadOriginal,
    required this.onChanged,
  });

  final bool isDark;
  final bool downloadOriginal;
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
              Icons.speed_rounded,
              size: 20,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fast Downloads (Original)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    downloadOriginal
                        ? 'Downloads bypass transcoding for maximum speed'
                        : 'Use transcoding to reduce download size',
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
              value: downloadOriginal,
              onChanged: onChanged,
              activeThumbColor: isDark ? Colors.white : Colors.black,
            ),
          ],
        ),
      ),
    );
  }
}
