import 'package:flutter/material.dart';

import '../../services/spotify_import_service.dart';
import '../../utils/constants.dart';

enum _RemovePhase { confirm, removing, done, error }

/// Deletes the signed-in account's Spotify import — the counterpart to the
/// import dialog's upload.
class SpotifyRemoveDialog extends StatefulWidget {
  const SpotifyRemoveDialog({super.key, required this.service});

  final SpotifyImportService service;

  @override
  State<SpotifyRemoveDialog> createState() => _SpotifyRemoveDialogState();
}

class _SpotifyRemoveDialogState extends State<SpotifyRemoveDialog> {
  _RemovePhase _phase = _RemovePhase.confirm;
  String _message = '';
  int _deleted = 0;

  Future<void> _remove() async {
    setState(() => _phase = _RemovePhase.removing);
    try {
      final deleted = await widget.service.removeImportedStats();
      if (!mounted) return;
      setState(() {
        _deleted = deleted;
        _phase = _RemovePhase.done;
      });
    } on SpotifyImportFailure catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not remove the imported Spotify stats.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _RemovePhase.error;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: const Text('Remove Spotify listening stats'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _buildContent(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _phase == _RemovePhase.removing
              ? null
              : () => Navigator.pop(context),
          child: Text(_phase == _RemovePhase.done ? 'Close' : 'Cancel'),
        ),
        if (_phase == _RemovePhase.confirm || _phase == _RemovePhase.error)
          ElevatedButton(
            onPressed: _remove,
            child: const Text('Remove import'),
          ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _RemovePhase.confirm:
        return const Text(
          'Every play imported from Spotify will be removed from the '
          'signed-in account. Listening Ariami tracked itself is kept, and '
          'you can import the same export again later.',
        );
      case _RemovePhase.removing:
        return const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Removing imported plays…')),
          ],
        );
      case _RemovePhase.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
            const SizedBox(width: 12),
            Expanded(child: Text(_message)),
          ],
        );
      case _RemovePhase.done:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _deleted == 0
                    ? 'This account had no Spotify-imported plays.'
                    : '$_deleted Spotify-imported '
                        '${_deleted == 1 ? 'play' : 'plays'} removed.',
              ),
            ),
          ],
        );
    }
  }
}
