import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../downloads_state.dart';

/// Top-of-screen card showing aggregate progress across the active batch.
/// Subscribes to the controller's [OverallProgressSummary] notifier so byte
/// ticks repaint only this card, not the section list.
class DownloadsSummaryCard extends StatelessWidget {
  const DownloadsSummaryCard({
    super.key,
    required this.isDark,
    required this.summary,
  });

  final bool isDark;
  final ValueListenable<OverallProgressSummary> summary;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OverallProgressSummary>(
      valueListenable: summary,
      builder: (context, value, _) {
        if (!value.hasActivity) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141414) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF222222) : const Color(0xFFEEEEEE),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _headlineText(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  Text(
                    '${value.percentage}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: value.totalSongs > 0 ? value.progress : null,
                  minHeight: 6,
                  backgroundColor: isDark
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFEEEEEE),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _headlineText(OverallProgressSummary value) {
    if (value.totalSongs > 0 && value.completedSongs <= value.totalSongs) {
      return 'Downloading ${value.completedSongs} of ${value.totalSongs}';
    }
    return 'Downloading ${value.inProgressSongs}';
  }
}
