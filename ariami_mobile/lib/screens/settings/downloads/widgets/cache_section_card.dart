import 'package:flutter/material.dart';

class CacheSectionCard extends StatelessWidget {
  const CacheSectionCard({
    super.key,
    required this.isDark,
    required this.cacheSizeMB,
    required this.cachedSongCount,
    required this.cacheLimitMB,
    required this.onLimitChanged,
    required this.onLimitChangeEnd,
    required this.onClearCache,
  });

  final bool isDark;
  final double cacheSizeMB;
  final int cachedSongCount;
  final int cacheLimitMB;
  final ValueChanged<double> onLimitChanged;
  final ValueChanged<double> onLimitChangeEnd;
  final VoidCallback onClearCache;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cached_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 10),
                Text(
                  'Media Cache',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cacheSizeMB.toStringAsFixed(1)} MB',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      'of $cacheLimitMB MB limit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Text(
                  '$cachedSongCount songs',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: cacheLimitMB > 0
                    ? (cacheSizeMB / cacheLimitMB).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 8,
                backgroundColor:
                    isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE),
                valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white : Colors.black),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: cacheLimitMB.toDouble(),
                      min: 100,
                      max: 2000,
                      divisions: 19,
                      label: '$cacheLimitMB MB',
                      activeColor: isDark ? Colors.white : Colors.black,
                      inactiveColor: isDark
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFEEEEEE),
                      onChanged: onLimitChanged,
                      onChangeEnd: onLimitChangeEnd,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: cacheSizeMB > 0 ? onClearCache : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                label: const Text(
                  'Clear Media Cache',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
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
            const SizedBox(height: 16),
            Text(
              'Cached content is automatically managed when you stream songs. Clearing cache won\'t affect your downloads.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
                height: 1.4,
              ),
            ),
          ],
        ),
    );
  }
}
