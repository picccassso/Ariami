import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/spotify_import_service.dart';

enum _ImportPhase { intro, analyzing, preview, uploading, done, error }

class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({
    super.key,
    required this.service,
    this.pickFolder,
  });

  final DesktopSpotifyImportService service;
  final Future<String?> Function()? pickFolder;

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  _ImportPhase _phase = _ImportPhase.intro;
  DesktopSpotifyImportPreview? _preview;
  DesktopSpotifyImportUploadResult? _uploadResult;
  String _message = '';
  int _sent = 0;

  Future<String?> _pickFolder() =>
      widget.pickFolder?.call() ??
      FilePicker.getDirectoryPath(
        dialogTitle: 'Choose your Spotify export folder',
      );

  Future<void> _selectAndAnalyze() async {
    final folderPath = await _pickFolder();
    if (folderPath == null) return;
    setState(() {
      _phase = _ImportPhase.analyzing;
      _message = 'Reading and matching your Spotify history…';
    });
    try {
      final preview = await widget.service.analyzeFolder(folderPath);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _phase = _ImportPhase.preview;
        _message = '';
      });
    } on DesktopSpotifyImportFailure catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not analyze the Spotify export.');
    }
  }

  Future<void> _upload() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _phase = _ImportPhase.uploading;
      _sent = 0;
      _message = 'Uploading plays…';
    });
    try {
      final result = await widget.service.upload(
        preview,
        onProgress: (sent, _) {
          if (mounted) setState(() => _sent = sent);
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadResult = result;
        _phase = _ImportPhase.done;
        _message = '';
      });
    } on DesktopSpotifyImportFailure catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError(
        'The upload was interrupted. Plays already uploaded are saved; '
        'retrying is safe.',
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _ImportPhase.error;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Spotify listening stats'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _buildContent(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _phase == _ImportPhase.uploading
              ? null
              : () => Navigator.pop(context),
          child: Text(_phase == _ImportPhase.done ? 'Close' : 'Cancel'),
        ),
        if (_phase == _ImportPhase.intro || _phase == _ImportPhase.error)
          ElevatedButton(
            onPressed: _selectAndAnalyze,
            child: const Text('Choose folder'),
          ),
        if (_phase == _ImportPhase.preview)
          ElevatedButton(
            onPressed: _upload,
            child: const Text('Import plays'),
          ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _ImportPhase.intro:
        return const Text(
          'Choose the unzipped Spotify Extended Streaming History folder. '
          'Ariami reads only Streaming_History_Audio_*.json files and shows '
          'a preview before uploading anything.',
        );
      case _ImportPhase.analyzing:
        return _busy(_message);
      case _ImportPhase.uploading:
        final total = _preview?.result.events.length ?? 0;
        return _busy('$_message $_sent of $total');
      case _ImportPhase.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(_message)),
          ],
        );
      case _ImportPhase.preview:
        final preview = _preview!;
        final tracks = preview.uniqueTrackCounts;
        final result = preview.result;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account: ${preview.accountUsername}'),
            const SizedBox(height: 16),
            Text('${result.events.length} eligible plays'),
            Text('${tracks.$1} library tracks matched'),
            Text('${tracks.$2} tracks not in your library'),
            Text(
              '${(result.playMatchRate * 100).toStringAsFixed(1)}% of plays matched',
            ),
            const SizedBox(height: 16),
            const Text(
              'Importing again is safe: Ariami uses stable IDs and will not '
              'double-count the same Spotify plays.',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        );
      case _ImportPhase.done:
        final result = _uploadResult!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 12),
                Text('Spotify listening stats imported.'),
              ],
            ),
            const SizedBox(height: 16),
            Text('${result.accepted} new plays added'),
            Text('${result.duplicates} existing plays skipped'),
            if (result.rejected > 0)
              Text('${result.rejected} invalid plays rejected'),
          ],
        );
    }
  }

  Widget _busy(String message) => Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(message)),
        ],
      );
}
