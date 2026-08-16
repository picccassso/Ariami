import 'package:flutter/material.dart';

import '../../../models/music_folder_validation_result.dart';
import '../../services/web_setup_service.dart';
import '../../utils/constants.dart';

/// Point the server at a different music folder without walking back through
/// setup.
///
/// Reuses the same [WebSetupService] calls the setup flow uses — suggestions,
/// validate, then save — so a path accepted here is a path setup would accept.
/// Pops the chosen path on success; the caller triggers the rescan.
class ChangeMusicFolderDialog extends StatefulWidget {
  const ChangeMusicFolderDialog({
    super.key,
    required this.setupService,
    this.currentPath,
  });

  final WebSetupService setupService;
  final String? currentPath;

  @override
  State<ChangeMusicFolderDialog> createState() =>
      _ChangeMusicFolderDialogState();
}

class _ChangeMusicFolderDialogState extends State<ChangeMusicFolderDialog> {
  late final TextEditingController _pathController =
      TextEditingController(text: widget.currentPath ?? '');

  List<MusicFolderValidationResult> _suggestions = const [];
  bool _isLoadingSuggestions = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final suggestions = await widget.setupService.getMusicFolderSuggestions();
    if (!mounted) return;
    setState(() {
      // Only offer paths that actually work, and never the current one.
      _suggestions = suggestions
          .where((s) => s.isValid && s.path != widget.currentPath)
          .toList(growable: false);
      _isLoadingSuggestions = false;
    });
  }

  Future<void> _save(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorMessage = 'Enter a folder path.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await widget.setupService.setMusicFolder(trimmed);
    if (!mounted) return;

    if (result.isValid) {
      Navigator.of(context).pop(result.path);
      return;
    }

    setState(() {
      _isSaving = false;
      _errorMessage = result.message?.isNotEmpty == true
          ? result.message
          : 'That path is not readable on the server.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change music folder'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose a folder on the machine running the server. Ariami '
                'rescans it straight away; your files are never moved or '
                'changed.',
                style: AppTheme.meta,
              ),
              const SizedBox(height: 18),
              Text('Path on the server', style: AppTheme.fieldLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _pathController,
                enabled: !_isSaving,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: InputDecoration(
                  hintText: '/path/to/your/music',
                  errorText: _errorMessage,
                  prefixIcon: const Icon(Icons.folder_open_rounded, size: 19),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
                onSubmitted: _isSaving ? null : _save,
              ),
              if (_isLoadingSuggestions) ...[
                const SizedBox(height: 18),
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ] else if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Found on this server', style: AppTheme.fieldLabel),
                const SizedBox(height: 8),
                for (final suggestion in _suggestions)
                  _SuggestionTile(
                    path: suggestion.path,
                    enabled: !_isSaving,
                    onTap: () {
                      _pathController.text = suggestion.path;
                      setState(() => _errorMessage = null);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : () => _save(_pathController.text),
          child: _isSaving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save and rescan'),
        ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.path,
    required this.enabled,
    required this.onTap,
  });

  final String path;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded,
                    size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    path,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
