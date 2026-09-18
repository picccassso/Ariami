import 'package:flutter/material.dart';

import '../../../../models/quality_settings.dart';
import '../../../../widgets/common/mini_player_aware_bottom_sheet.dart';

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

  IconData _getIconForQuality(DownloadQuality quality) {
    switch (quality) {
      case DownloadQuality.original:
        return Icons.audio_file_rounded;
      case DownloadQuality.high:
        return Icons.high_quality_rounded;
      case DownloadQuality.medium:
        return Icons.sd_rounded;
      case DownloadQuality.low:
        return Icons.data_saver_on_rounded;
    }
  }

  void _showQualityPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedQuality = _effectiveQuality;

    showAriamiSheet<void>(
      context: context,
      backgroundColor: colorScheme.surface,
      header: const AriamiSheetSectionTitle('Download quality'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...DownloadQuality.values.map((quality) {
            final isSelected = quality == selectedQuality;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                child: ListTile(
                  leading: Icon(
                    _getIconForQuality(quality),
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(
                    quality.displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    quality.description,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onPrimary.withValues(alpha: 0.7)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: colorScheme.onPrimary,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    onQualityChanged?.call(quality);
                    onChanged?.call(quality == DownloadQuality.original);
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
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
