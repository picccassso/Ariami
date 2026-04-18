import 'package:flutter/material.dart';

import '../../../../models/quality_settings.dart';

class DownloadModeCard extends StatelessWidget {
  const DownloadModeCard({
    super.key,
    required this.isDark,
    required this.downloadQuality,
    required this.downloadOriginal,
    required this.onChanged,
  });

  final bool isDark;
  final StreamingQuality downloadQuality;
  final bool downloadOriginal;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  downloadQuality != StreamingQuality.high
                      ? 'Set Download Quality to High (Original) to enable this option'
                      : downloadOriginal
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
            value: downloadQuality == StreamingQuality.high && downloadOriginal,
            onChanged: onChanged,
            activeThumbColor: isDark ? Colors.white : Colors.black,
          ),
        ],
      ),
    );
  }
}
