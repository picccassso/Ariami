import 'package:flutter/material.dart';

import 'package:ariami_core/models/playlist_suggestion.dart';

import '../../utils/constants.dart';
import '../ui/section.dart';

/// Dashboard card for likely-playlist folders found by the scanner.
///
/// Suggestions are advisory: nothing is imported until the user clicks
/// Import here (Ignore hides the folder from future scans). Hidden entirely
/// when there are no pending suggestions.
class SuggestedPlaylistsSection extends StatelessWidget {
  const SuggestedPlaylistsSection({
    super.key,
    required this.suggestions,
    required this.decidingFolderPaths,
    required this.onImport,
    required this.onIgnore,
  });

  final List<PlaylistSuggestion> suggestions;
  final Set<String> decidingFolderPaths;
  final void Function(PlaylistSuggestion suggestion) onImport;
  final void Function(PlaylistSuggestion suggestion) onIgnore;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Section(
      title: 'Suggested playlists',
      description: 'These folders look like playlists. Import treats a folder '
          'like a [PLAYLIST] folder on every scan; Ignore hides it for good.',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final suggestion in suggestions) ...[
              _SuggestionRow(
                suggestion: suggestion,
                isDeciding:
                    decidingFolderPaths.contains(suggestion.folderPath),
                onImport: () => onImport(suggestion),
                onIgnore: () => onIgnore(suggestion),
              ),
              if (suggestion != suggestions.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.isDeciding,
    required this.onImport,
    required this.onIgnore,
  });

  final PlaylistSuggestion suggestion;
  final bool isDeciding;
  final VoidCallback onImport;
  final VoidCallback onIgnore;

  String get _countsLine {
    final parts = <String>[
      '${suggestion.songCount} songs',
      '${suggestion.artistCount} artists',
      '${suggestion.albumCount} albums',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.queue_music_rounded,
            color: AppTheme.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        suggestion.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (suggestion.missingTags) ...[
                      const SizedBox(width: 8),
                      const _MissingTagsBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Tooltip(
                  message: suggestion.reasons.isEmpty
                      ? suggestion.folderPath
                      : '${suggestion.folderPath}\n'
                          '${suggestion.reasons.join('\n')}',
                  child: Text(
                    _countsLine,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isDeciding)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else ...[
            TextButton(
              onPressed: onIgnore,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
              ),
              child: const Text('Ignore'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onImport,
              child: const Text('Import'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MissingTagsBadge extends StatelessWidget {
  const _MissingTagsBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.45)),
      ),
      child: const Text(
        'Tags missing — review before importing',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.warning,
        ),
      ),
    );
  }
}
