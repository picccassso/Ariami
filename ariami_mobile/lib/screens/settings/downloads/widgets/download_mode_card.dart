import 'package:flutter/material.dart';

import '../../../../models/quality_settings.dart';
import '../../../../widgets/settings/option_sheet.dart';

class DownloadModeCard extends StatelessWidget {
  const DownloadModeCard({
    super.key,
    required this.isDark,
    this.currentQuality,
    this.onQualityChanged,
    this.downloadQuality,
    this.downloadOriginal,
    this.onChanged,
  });

  final bool isDark;
  final DownloadQuality? currentQuality;
  final ValueChanged<DownloadQuality>? onQualityChanged;
  final StreamingQuality? downloadQuality;
  final bool? downloadOriginal;
  final ValueChanged<bool>? onChanged;

  DownloadQuality get _effectiveQuality {
    if (currentQuality != null) return currentQuality!;
    if (downloadOriginal == true) return DownloadQuality.original;
    if (downloadQuality != null) {
      return DownloadQuality.fromSettings(
        quality: downloadQuality!,
        isOriginal: downloadOriginal ?? false,
      );
    }
    return DownloadQuality.high;
  }

  void _showQualityPicker(BuildContext context) {
    showOptionSheet<DownloadQuality>(
      context,
      header: 'Download quality',
      values: DownloadQuality.values,
      current: _effectiveQuality,
      iconOf: downloadQualityIcon,
      titleOf: (q) => q.displayName,
      subtitleOf: (q) => q.description,
      onSelected: (quality) {
        onQualityChanged?.call(quality);
        onChanged?.call(quality == DownloadQuality.original);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final quality = _effectiveQuality;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showQualityPicker(context),
        child: Padding(
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
                      'Download Quality',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quality.description,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        quality.displayName,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
