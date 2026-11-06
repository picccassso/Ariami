import 'package:ariami_core/utils/format.dart';
import 'package:flutter/material.dart';

import '../../services/library_upload_service.dart';
import '../../utils/constants.dart';
import 'library_folder_picker.dart';

enum _UploadPhase { choosing, uploading, done }

/// Uploads dropped or chosen files into a folder of the server's library.
/// Files can be dropped anywhere on the page while the dialog is open.
class LibraryUploadDialog extends StatefulWidget {
  const LibraryUploadDialog({
    super.key,
    required this.service,
    this.initialFiles = const [],
  });

  final LibraryUploadService service;
  final List<LibraryUploadFile> initialFiles;

  @override
  State<LibraryUploadDialog> createState() => _LibraryUploadDialogState();
}

class _LibraryUploadDialogState extends State<LibraryUploadDialog> {
  late final void Function() _stopListening;
  final Map<String, LibraryUploadFile> _chosen = {};
  LibraryUploadTargets? _targets;
  String? _loadError;
  String _folder = '';
  final List<String> _newFolders = [];
  _UploadPhase _phase = _UploadPhase.choosing;
  int _sentBytes = 0;
  int _currentIndex = 0;
  final Map<LibraryUploadResult, int> _resultCounts = {};
  final List<String> _failedPaths = [];

  /// Chosen files the server accepts; the rest are counted as ignored.
  List<LibraryUploadFile> get _files =>
      _chosen.values.where((f) => _targets?.accepts(f) ?? false).toList();

  @override
  void initState() {
    super.initState();
    _addFiles(widget.initialFiles);
    _stopListening = listenForDroppedFiles(_addFiles);
    _loadTargets();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    try {
      final targets = await widget.service.fetchTargets();
      if (mounted) setState(() => _targets = targets);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Could not reach the music folder.');
      }
    }
  }

  void _addFiles(List<LibraryUploadFile> files) {
    if (_phase != _UploadPhase.choosing || !mounted) return;
    setState(() {
      for (final file in files) {
        _chosen[file.relativePath] = file;
      }
    });
  }

  /// Adds a folder under the selected one and selects it. It only exists
  /// locally until a file is uploaded into it.
  Future<void> _promptNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title:
            Text('New folder in ${_folder.isEmpty ? 'Library root' : _folder}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    // The server rejects these too; skip them rather than fail every upload.
    if (trimmed.isEmpty || trimmed.startsWith('.') || trimmed.contains('/')) {
      return;
    }
    final path = _folder.isEmpty ? trimmed : '$_folder/$trimmed';
    setState(() {
      if (!_targets!.folders.contains(path)) _newFolders.add(path);
      _folder = path;
    });
  }

  Future<void> _upload() async {
    final files = _files;
    setState(() => _phase = _UploadPhase.uploading);
    var finishedBytes = 0;
    for (final (index, file) in files.indexed) {
      setState(() => _currentIndex = index);
      final result = await widget.service.upload(
        file,
        folder: _folder,
        onProgress: (sent) {
          if (mounted) setState(() => _sentBytes = finishedBytes + sent);
        },
      );
      finishedBytes += file.size;
      _resultCounts[result] = (_resultCounts[result] ?? 0) + 1;
      if (result == LibraryUploadResult.failed) {
        _failedPaths.add(file.relativePath);
      }
    }
    if (mounted) setState(() => _phase = _UploadPhase.done);
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return AlertDialog(
      backgroundColor: AppTheme.surfaceBlack,
      title: const Text('Upload music'),
      // A fixed width: AlertDialog sizes content by intrinsic width, which
      // the folder tree and file list cannot report.
      content: SizedBox(
        width: 520,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: switch (_phase) {
            _UploadPhase.choosing => _buildChoosing(files),
            _UploadPhase.uploading => _buildUploading(files),
            _UploadPhase.done => _buildDone(),
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _phase == _UploadPhase.uploading
              ? null
              : () => Navigator.pop(context),
          child: Text(_phase == _UploadPhase.done ? 'Close' : 'Cancel'),
        ),
        if (_phase == _UploadPhase.choosing)
          ElevatedButton(
            onPressed: files.isEmpty ? null : _upload,
            child: Text(files.isEmpty ? 'Upload' : 'Upload ${files.length}'),
          ),
      ],
    );
  }

  Widget _buildChoosing(List<LibraryUploadFile> files) {
    final targets = _targets;
    if (_loadError != null) return Text(_loadError!);
    if (targets == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final ignored = _chosen.length - files.length;
    final totalBytes = files.fold(0, (sum, f) => sum + f.size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Upload to: ${_folder.isEmpty ? 'Library root' : _folder}',
                style: AppTheme.fieldLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _promptNewFolder,
              icon: const Icon(Icons.create_new_folder_rounded, size: 17),
              label: const Text('New folder'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LibraryFolderPicker(
          folders: [...targets.folders, ..._newFolders]
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
          selected: _folder,
          onSelected: (folder) => setState(() => _folder = folder),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderStrong),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Column(
            children: [
              const Icon(Icons.upload_file_rounded,
                  size: 32, color: AppTheme.textSecondary),
              const SizedBox(height: 8),
              const Text(
                'Drop music files or folders anywhere on this page',
                textAlign: TextAlign.center,
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () async =>
                        _addFiles(await pickFilesForUpload()),
                    child: const Text('Choose files'),
                  ),
                  TextButton(
                    onPressed: () async =>
                        _addFiles(await pickFilesForUpload(folder: true)),
                    child: const Text('Choose folder'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_chosen.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${_fileCount(files.length)} · ${formatBytes(totalBytes)}'),
          if (ignored > 0)
            Text(
              '$ignored ignored: not music, lyrics or cover art',
              style: AppTheme.meta,
            ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final file in files)
                  Text(file.relativePath, style: AppTheme.meta),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUploading(List<LibraryUploadFile> files) {
    final totalBytes = files.fold(0, (sum, f) => sum + f.size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: totalBytes == 0 ? null : _sentBytes / totalBytes,
        ),
        const SizedBox(height: 12),
        Text('Uploading ${_currentIndex + 1} of ${files.length} · '
            '${formatBytes(_sentBytes)} of ${formatBytes(totalBytes)}'),
        Text(
          files[_currentIndex].relativePath,
          style: AppTheme.meta,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDone() {
    int count(LibraryUploadResult result) => _resultCounts[result] ?? 0;
    final failed = count(LibraryUploadResult.failed);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              failed == 0 ? Icons.check_circle_rounded : Icons.error_outline,
              color: failed == 0 ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(width: 12),
            Text('${_fileCount(count(LibraryUploadResult.uploaded))} uploaded'),
          ],
        ),
        const SizedBox(height: 16),
        if (count(LibraryUploadResult.alreadyExists) > 0)
          Text('${count(LibraryUploadResult.alreadyExists)} skipped: '
              'already in the library'),
        if (failed > 0) ...[
          Text('$failed failed:'),
          for (final path in _failedPaths.take(10))
            Text(path, style: AppTheme.meta),
        ],
        const SizedBox(height: 16),
        const Text(
          'New songs show up in the library within a few seconds.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  String _fileCount(int count) => count == 1 ? '1 file' : '$count files';
}
