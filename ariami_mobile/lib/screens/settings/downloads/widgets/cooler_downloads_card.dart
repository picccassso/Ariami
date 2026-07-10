import 'package:flutter/material.dart';

class CoolerDownloadsCard extends StatelessWidget {
  const CoolerDownloadsCard({
    super.key,
    required this.isDark,
    required this.coolerDownloads,
    required this.onChanged,
  });

  final bool isDark;
  final bool coolerDownloads;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.ac_unit_rounded,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cooler Downloads',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  coolerDownloads
                      ? 'Downloads are paced to reduce heat and battery drain. Large downloads take longer.'
                      : 'Pace bulk downloads to keep the phone cooler, at the cost of speed.',
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
            value: coolerDownloads,
            onChanged: onChanged,
            activeThumbColor: isDark ? Colors.white : Colors.black,
          ),
        ],
      ),
    );
  }
}
