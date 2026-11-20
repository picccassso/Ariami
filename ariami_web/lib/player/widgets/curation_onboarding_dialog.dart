import 'package:ariami_core/models/library_curation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_controller.dart';
import '../theme/player_theme.dart';
import 'curate_library_dialog.dart';

/// Shown once after a non-owner account signs in for the first time with an
/// uncompleted curation state.
Future<void> showCurationOnboardingDialog(BuildContext context) async {
  final library = context.read<LibraryController>();
  final action = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _CurationOnboardingDialog(),
  );
  if (!context.mounted) return;
  if (action == 'full') {
    await library.completeCurationOnboardingFull();
  } else if (action == 'curate') {
    await showPlayerLibraryCurationDialog(
      context,
      initialModeOverride: LibraryCurationMode.curated,
    );
  }
}

class _CurationOnboardingDialog extends StatelessWidget {
  const _CurationOnboardingDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: const Text('Set Up Your Library'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how your personal library starts on this server. You '
              'can change this anytime in Settings -> My Library.',
              style: TextStyle(color: colors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            _ChoiceTile(
              icon: Icons.library_music_rounded,
              title: 'Include Everything',
              subtitle:
                  'Show the whole server catalog and new music automatically. '
                  'Hide individual items whenever you want.',
              onTap: () => Navigator.of(context).pop('full'),
            ),
            const SizedBox(height: 10),
            _ChoiceTile(
              icon: Icons.tune_rounded,
              title: 'Pick My Artists & Albums',
              subtitle:
                  'Start clean and choose only the artists, albums, server '
                  'playlists, and songs you want in your library.',
              onTap: () => Navigator.of(context).pop('curate'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('full'),
          child: const Text('Decide later (Include Everything)'),
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
