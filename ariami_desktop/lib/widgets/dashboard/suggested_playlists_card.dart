import 'package:ariami_core/models/playlist_suggestion.dart';
import 'package:flutter/material.dart';

/// Likely-playlist folders found by the last library scan.
///
/// Suggestions are advisory: nothing is imported until the owner presses
/// Import (Ignore hides the folder from future scans). Renders nothing when
/// there are no pending suggestions.
class SuggestedPlaylistsCard extends StatelessWidget {
  const SuggestedPlaylistsCard({
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

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggested Playlists',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'These folders look like playlists. Import treats a folder like a '
          '[PLAYLIST] folder on every scan; Ignore hides it for good.',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (var i = 0; i < suggestions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _SuggestionRow(
                    suggestion: suggestions[i],
                    isDeciding:
                        decidingFolderPaths.contains(suggestions[i].folderPath),
                    onImport: () => onImport(suggestions[i]),
                    onIgnore: () => onIgnore(suggestions[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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

  String get _countsLine => '${suggestion.songCount} songs · '
      '${suggestion.artistCount} artists · '
      '${suggestion.albumCount} albums';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Row(
      children: [
        Icon(Icons.queue_music_rounded, color: muted, size: 22),
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
                  style: TextStyle(fontSize: 13, color: muted),
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
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          TextButton(
            onPressed: onIgnore,
            style: TextButton.styleFrom(foregroundColor: muted),
            child: const Text('Ignore'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: onImport, child: const Text('Import')),
        ],
      ],
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
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
      ),
      child: Text(
        'Tags missing — review before importing',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.orange.shade300,
        ),
      ),
    );
  }
}
