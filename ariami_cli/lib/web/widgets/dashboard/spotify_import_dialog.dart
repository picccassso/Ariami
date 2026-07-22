import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/spotify_import_service.dart';
import '../../utils/constants.dart';

enum _ImportPhase { intro, analyzing, preview, uploading, done, error }

class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({
    super.key,
    required this.service,
    this.pickFiles,
  });

  final SpotifyImportService service;
  final Future<FilePickerResult?> Function()? pickFiles;

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  _ImportPhase _phase = _ImportPhase.intro;
  SpotifyImportPreview? _preview;
  SpotifyImportUploadResult? _uploadResult;
  String _message = '';
  int _sent = 0;

  Future<FilePickerResult?> _pickFiles() =>
      widget.pickFiles?.call() ??
      FilePicker.pickFiles(
        dialogTitle: 'Choose Spotify audio-history JSON files',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: true,
        withData: true,
      );

  Future<void> _selectAndAnalyze() async {
    final selection = await _pickFiles();
    if (selection == null) return;
    setState(() {
      _phase = _ImportPhase.analyzing;
      _message = 'Reading and matching your Spotify history…';
    });
    try {
      final records = SpotifyImportService.decodeSelectedFiles(selection.files);
      final preview = await widget.service.analyze(records);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _phase = _ImportPhase.preview;
        _message = '';
      });
    } on SpotifyImportFailure catch (error) {
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
    } on SpotifyImportFailure catch (error) {
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
      backgroundColor: AppTheme.surfaceBlack,
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
          child: Text(_phase == _ImportPhase.done ? 'CLOSE' : 'CANCEL'),
        ),
        if (_phase == _ImportPhase.intro || _phase == _ImportPhase.error)
          ElevatedButton(
            onPressed: _selectAndAnalyze,
            child: const Text('CHOOSE FILES'),
          ),
        if (_phase == _ImportPhase.preview)
          ElevatedButton(
            onPressed: _upload,
            child: const Text('IMPORT PLAYS'),
          ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _ImportPhase.intro:
        return const Text(
          'Select all Streaming_History_Audio_*.json files from your '
          'unzipped Spotify Extended Streaming History export. Ariami will '
          'match tracks to your library and show a preview before uploading.',
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
                '${(result.playMatchRate * 100).toStringAsFixed(1)}% of plays matched'),
            const SizedBox(height: 16),
            const Text(
              'Importing again is safe: Ariami uses stable IDs and will not '
              'double-count the same Spotify plays.',
              style: TextStyle(color: AppTheme.textSecondary),
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
