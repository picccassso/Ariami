import 'package:flutter/material.dart';

import '../../models/quality_settings.dart';
import '../common/mini_player_aware_bottom_sheet.dart';

/// A selectable option row used in settings bottom sheets.
class OptionSheetTile extends StatelessWidget {
  const OptionSheetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: selected ? colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: ListTile(
          leading: Icon(
            icon,
            color:
                selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            size: 20,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected
                  ? colorScheme.onPrimary.withValues(alpha: 0.7)
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: selected
              ? Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.onPrimary,
                  size: 20,
                )
              : null,
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing [values] as [OptionSheetTile]s; tapping one closes the
/// sheet and calls [onSelected].
void showOptionSheet<T>(
  BuildContext context, {
  required String header,
  required List<T> values,
  required T current,
  required IconData Function(T) iconOf,
  required String Function(T) titleOf,
  required String Function(T) subtitleOf,
  required void Function(T) onSelected,
}) {
  showAriamiSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    header: AriamiSheetSectionTitle(header),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final value in values)
          OptionSheetTile(
            icon: iconOf(value),
            title: titleOf(value),
            subtitle: subtitleOf(value),
            selected: value == current,
            onTap: () {
              Navigator.pop(context);
              onSelected(value);
            },
          ),
      ],
    ),
  );
}

/// Icon for a download-quality picker row.
IconData downloadQualityIcon(DownloadQuality quality) {
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
