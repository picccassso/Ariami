import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../../../models/api_models.dart';
import '../../../utils/image_decode.dart';
import '../../../utils/image_upload.dart';

class EditPlaylistDialog extends StatefulWidget {
  final PlaylistModel playlist;

  const EditPlaylistDialog({
    super.key,
    required this.playlist,
  });

  @override
  State<EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<EditPlaylistDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  String? _newImagePath;
  bool _removeImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist.name);
    _descController =
        TextEditingController(text: widget.playlist.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final pickedPath = result.files.first.path;
      if (pickedPath != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final playlistImagesDir = Directory('${appDir.path}/playlist_images');
        if (!await playlistImagesDir.exists()) {
          await playlistImagesDir.create(recursive: true);
        }
        // Camera originals over the server's cap would never sync, so store
        // a downscaled PNG copy instead.
        final original = await File(pickedPath).readAsBytes();
        final bytes = await downscaleIfOversized(original);
        final ext =
            identical(bytes, original) ? path.extension(pickedPath) : '.png';
        final newFileName =
            '${widget.playlist.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
        final destPath = '${playlistImagesDir.path}/$newFileName';
        await File(destPath).writeAsBytes(bytes, flush: true);
        setState(() {
          _newImagePath = destPath;
          _removeImage = false;
        });
      }
    }
  }

  Widget _buildImageWidget() {
    final currentImagePath = _removeImage
        ? null
        : (_newImagePath ?? widget.playlist.customImagePath);

    if (currentImagePath != null && File(currentImagePath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          image: resizedForDisplay(
            context,
            FileImage(File(currentImagePath)),
            120,
          ),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      );
    } else {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.queue_music,
          size: 48,
          color: Colors.grey,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage =
        (_newImagePath != null || widget.playlist.customImagePath != null) &&
            !_removeImage;

    return AlertDialog(
      title: const Text('Edit Playlist'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: _buildImageWidget(),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Change Photo'),
            ),
            if (hasImage)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _removeImage = true;
                    _newImagePath = null;
                  });
                },
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Remove Photo'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EditResult(
              name: _nameController.text.trim(),
              description: _descController.text.trim().isEmpty
                  ? null
                  : _descController.text.trim(),
              newImagePath: _newImagePath,
              clearCustomImage: _removeImage,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditResult {
  final String name;
  final String? description;
  final String? newImagePath;
  final bool clearCustomImage;

  _EditResult({
    required this.name,
    this.description,
    this.newImagePath,
    required this.clearCustomImage,
  });
}

Future<EditPlaylistResult?> showEditPlaylistDialog(
  BuildContext context,
  PlaylistModel playlist,
) async {
  final result = await showDialog<_EditResult>(
    context: context,
    builder: (context) => EditPlaylistDialog(playlist: playlist),
  );

  if (result == null) return null;

  return EditPlaylistResult(
    name: result.name,
    description: result.description,
    newImagePath: result.newImagePath,
    clearCustomImage: result.clearCustomImage,
  );
}

class EditPlaylistResult {
  final String name;
  final String? description;
  final String? newImagePath;
  final bool clearCustomImage;

  EditPlaylistResult({
    required this.name,
    this.description,
    this.newImagePath,
    required this.clearCustomImage,
  });
}
