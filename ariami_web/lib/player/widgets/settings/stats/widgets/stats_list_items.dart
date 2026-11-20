import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/connection_controller.dart';
import '../../../../theme/player_theme.dart';
import '../../../artwork.dart';
import '../../settings_widgets.dart';
import '../stats_models.dart';

class StatsTab extends StatelessWidget {
  const StatsTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SettingsChoiceChip(label: label, selected: selected, onTap: onTap);
  }
}

class StatsMessage extends StatelessWidget {
  const StatsMessage({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 34, color: context.colors.textSecondary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// One entry of a ranking: the rank set large in the display face, the
/// cover, the title over its artist, and a quiet figure on the right. Tapping
/// it runs [onTap] when given (the home page plays the song).
class ListeningRankRow extends StatelessWidget {
  const ListeningRankRow({
    super.key,
    required this.rank,
    required this.item,
    this.onTap,
  });

  final int rank;
  final ListeningRankItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final client = context.read<ConnectionController>().client;
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      mouseCursor:
          onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                '$rank',
                textAlign: TextAlign.right,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: PlayerTheme.display(30, color: colors.textSecondary)
                    .copyWith(fontFeatures: PlayerTheme.tabular),
              ),
            ),
            const SizedBox(width: 18),
            Artwork(
              client: client,
              albumId: item.albumId,
              songId: item.albumId == null ? item.songId : null,
              size: 48,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 13.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              item.detail,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13.5,
                fontFeatures: PlayerTheme.tabular,
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}
